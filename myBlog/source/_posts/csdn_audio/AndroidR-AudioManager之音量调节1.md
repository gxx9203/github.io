---
link: https://blog.csdn.net/l328873524/article/details/117432245
title: Android R- AudioManager之音量调节(一)
description: 前言说到AudioManager的音量调节，首先就要说下音量的初始化，我们知道AudioManager只是提供了接口的API，其音量调节的核心逻辑都是在AudioService中实现的。那么今天就先说说AudioService。正文AudioService作为一个SystemServer它的音量是如何初始化起来的？说到音量初始化先看几个数组Max Volume所有streamType对应的最大音量  /** Maximum volume index values for audio stre
keywords: Android R- AudioManager之音量调节(一)
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2021-06-01T16:37:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=43 sentences=36, words=439
---
关于音量调节我们知道有AudioManager的软件调节和CarAudioManager的硬件调节，今天先聊聊AudioManager的软件音量调节。

关于AudioManager中音量调节的API主要有如下两个：

adjustVolume偏向一些按键的音量调节，比如手机上音量+-的硬按键控制的音量调节。
setStreamVolume更像是settings中的音量bar进行的音量调节。
说这俩函数前先看下volume几个相关的数组。

* Max Volume
所有streamType对应的最大音量

```java

    protected static int[] MAX_STREAM_VOLUME = new int[] {
        5,
        7,
        7,
        15,
        7,
        7,
        15,
        7,
        15,
        15,
        15,
        15
    };
```

* Min Volume
所有streamType对应的最小音量

```java

    protected static int[] MIN_STREAM_VOLUME = new int[] {
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0
    };
```

* Default Volume
注意默认音量定义在AudioSystem中

```java
    public static int[] DEFAULT_STREAM_VOLUME = new int[] {
        4,
        7,
        5,
        5,
        6,
        5,
        7,
        7,
        5,
        5,
        5,
        5,
    };
```

我们知道了每个streamType对应的最大、最小以及默认的音量，还有个很重的数组

* Volume Alias

```java
    private final int[] STREAM_VOLUME_ALIAS_VOICE = new int[] {
        AudioSystem.STREAM_VOICE_CALL,
        AudioSystem.STREAM_RING,
        AudioSystem.STREAM_RING,
        AudioSystem.STREAM_MUSIC,
        AudioSystem.STREAM_ALARM,
        AudioSystem.STREAM_RING,
        AudioSystem.STREAM_BLUETOOTH_SCO,
        AudioSystem.STREAM_RING,
        AudioSystem.STREAM_RING,
        AudioSystem.STREAM_MUSIC,
        AudioSystem.STREAM_MUSIC,
        AudioSystem.STREAM_MUSIC
    };
```

ALIAS别名，这个主要是将streamType进行了分组，相同别名的音量一组。如streamType是TTS和Music的就是一组，同一组的音源音量一起调节，我们调节了STREAM_MUSIC的音量，那么STREAM_TTS的音量也会同步变更。
接下来就看下具体音量调节的流程吧。

调节当前音源的音量，AudioService中实现adjustStreamVolume的逻辑比较复杂，因为随着Android版本的不断迭代，功能的不断增多。因此逻辑也是越来越复杂，比如震动下的铃声调节、勿扰模式下的铃声调节，以及特殊StreamType的特殊处理，这里只说下大体的流程吧。
首先是step的计算，即每次调节音量的步长。

```java
 step = rescaleStep(10, streamType, streamTypeAlias);
```

看下rescaleStep这个函数：

```java
    private int rescaleStep(int step, int srcStream, int dstStream) {
        int srcRange = getIndexRange(srcStream);
        int dstRange = getIndexRange(dstStream);
        if (srcRange == 0) {
            Log.e(TAG, "rescaleStep : index range should not be zero");
            return 0;
        }

        return ((step * dstRange + srcRange / 2) / srcRange);
    }
```

srcStream表示调节的streamType，dstStream表示当前音量组的streamType，举个例子如果当前调节的srcStream是STREAM_TTS那么通过STREAM_VOLUME_ALIAS_VOICE 我们可以知道dstStream是STREAM_MUSIC。

```java
    private int getIndexRange(int streamType) {
        return (mStreamStates[streamType].getMaxIndex() - mStreamStates[streamType].getMinIndex());
    }
```

如果srcStream音量最大值减去最小值不是0，那么就说明这个streamType的音量是可以调节的，那么它的步长就是((step * dstRange + srcRange / 2) / srcRange)根据上面的数组就很容易算出step来了。
拿到step，在根据direction然后调用VolumeStreamState的adjustIndex，而adjustIndex又会调用setIndex

```java
        public boolean adjustIndex(int deltaIndex, int device, String caller,
                boolean hasModifyAudioSettings) {
            return setIndex(getIndex(device) + deltaIndex, device, caller,
                    hasModifyAudioSettings);
        }
```

setIndex中主要做音量处理，以及发送音量变化的广播。这里多说一句音量变更后存储在mIndexMap中。

```java
mIndexMap.put(device, index)
```

可以看到音量的存储并不是根据streamType来的，而是根据device存储的，这就解释了我们在播放音乐的时候外放和插入耳机播放时音量不一致的原因了。
因为一个streamType可能对应多个Device即，一个streamType可能存在多个音量。

音量更新完后便是给子线程发 MSG_SET_DEVICE_VOLUME消息来调节音量。 子线程收到音量调节消息后调用VolumeStreamState的setDeviceVolume

```java
     void setDeviceVolume(VolumeStreamState streamState, int device) {

        synchronized (VolumeStreamState.class) {

            streamState.applyDeviceVolume_syncVSS(device);

            int numStreamTypes = AudioSystem.getNumStreamTypes();
            for (int streamType = numStreamTypes - 1; streamType >= 0; streamType--) {
                if (streamType != streamState.mStreamType &&
                        mStreamVolumeAlias[streamType] == streamState.mStreamType) {

                    int streamDevice = getDeviceForStream(streamType);
                    if ((device != streamDevice) && mAvrcpAbsVolSupported
                            && AudioSystem.DEVICE_OUT_ALL_A2DP_SET.contains(device)) {
                        mStreamStates[streamType].applyDeviceVolume_syncVSS(device);
                    }
                    mStreamStates[streamType].applyDeviceVolume_syncVSS(streamDevice);
                }
            }
        }

        sendMsg(mAudioHandler,
                MSG_PERSIST_VOLUME,
                SENDMSG_QUEUE,
                device,
                0,
                streamState,
                PERSIST_DELAY);

    }
```

这里主要做了三步，先看第一步即设置音量applyDeviceVolume_syncVSS将音量通过AudioSystem设置到native的AudioPolicyManager中；第二步是 mStreamStates[streamType].applyDeviceVolume_syncVSS(streamDevice)即设置相同组别的其他streamType的音量；最后一步发送MSG_PERSIST_VOLUME消息。将音量保存起来。
这样adjustVolume的流程就走完了。

设置指定streamType的音量。和adjustVolume的流程类似，但是相对adjustVolume而言setStreamVolume直接在AudioManager中调用到AudioService中的setStreamVolume。然后一些特殊的判断后会调用到onSetStreamVolume

```java
    private void onSetStreamVolume(int streamType, int index, int flags, int device,
            String caller, boolean hasModifyAudioSettings) {
        final int stream = mStreamVolumeAlias[streamType];
        setStreamVolumeInt(stream, index, device, false, caller, hasModifyAudioSettings);

        if (((flags & AudioManager.FLAG_ALLOW_RINGER_MODES) != 0) ||
                (stream == getUiSoundsStreamType())) {
            setRingerMode(getNewRingerMode(stream, index, flags),
                    TAG + ".onSetStreamVolume", false );
        }

        if (streamType != AudioSystem.STREAM_BLUETOOTH_SCO) {
            mStreamStates[stream].mute(index == 0);
        }
    }
```

然后是setStreamVolumeInt，然后streamState.setIndex到这里就和adjustVolume的逻辑相同了。

AudioManager的音量调节无论是adjustVolume还是setStreamVolume其实核心逻辑都是一样的，

* 更新VolumeStreamState中index，并存入mIndexMap中（主要为了getStreamVolume使用），将index通过AudioSystem设置下去
* 更新同组别的其他streamType的音量，音量组别可以通过int[] STREAM_VOLUME_ALIAS_VOICE查看
* 音量存储到数据库中
以上，欢迎大家一起沟通讨论喜欢就点下关注吧
