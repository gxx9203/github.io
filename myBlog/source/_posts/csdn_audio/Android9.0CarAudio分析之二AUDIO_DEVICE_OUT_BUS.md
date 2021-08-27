---
link: https://blog.csdn.net/l328873524/article/details/103001243
title: Android9.0CarAudio分析之而AUDIO_DEVICE_OUT_BUS
description: 最近这几年一直从事车载相关的开发，国内一般车载项目使用最多的系统目前基本应该就是Andoid了，尤其新兴的一些新能源汽车基本搭载的车载系统都是基于Android深度定制的。其实谷歌也搞了套车载东西，今天我们继续说说与汽车相关的 Android的音频架构。正题上一篇分析了CarAudioService的启动过程，今天继续，先分析下CarAudioService的init过程...
keywords: Android9.0CarAudio分析之而AUDIO_DEVICE_OUT_BUS
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2019-11-10T15:37:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=32 sentences=80, words=489
---
最近这几年一直从事车载相关的开发，国内一般车载项目使用最多的系统目前基本应该就是Andoid了，尤其新兴的一些新能源汽车基本搭载的车载系统都是基于Android深度定制的。其实谷歌也搞了套车载东西，今天我们继续说说与汽车相关的 Android的音频架构。

上一篇分析了CarAudioService的启动过程，今天继续，先分析下CarAudioService的init过程，相比于Android8.0，这部分改动还是挺大的。

```java
    @Override
    public void init() {
        synchronized (mImplLock) {
            if (!mUseDynamicRouting) {
                Log.i(CarLog.TAG_AUDIO, "Audio dynamic routing not configured, run in legacy mode");
                setupLegacyVolumeChangedListener();
            } else {
                setupDynamicRouting();
                setupVolumeGroups();
            }
        }
    }
```

如果我们使用的是AUDIO_DEVICE_OUT_BUS，那么mUseDynamicRouting这个值一定是true的，mUseDynamicRouting是怎么来的呢？

```java
mUseDynamicRouting = mContext.getResources().getBoolean(R.bool.audioUseDynamicRouting);
```

是在CarAudioService的构造函数中，通过xml读出来的，如果我们想使用AUDIO_DEVICE_OUT_BUS这种方式来实现音频输出策略，记得把这个值改为true

```java
packages/services/Car/service/res/values/config.xml
<bool name="audioUseDynamicRouting">false</bool>
```

但很少有人会改动这个目录下的xml，通常厂商在做定制的时候，一般都会通过在device目录下overlay的方式来实现修改。
其实CarAudioService的init只做了两件事情，setupDynamicRouting()和 setupVolumeGroups()，我们今天的重点就是setupDynamicRouting()，先看下代码：

```java
    private void setupDynamicRouting() {

        final IAudioControl audioControl = getAudioControl();
        if (audioControl == null) {
            return;
        }

        AudioPolicy audioPolicy = getDynamicAudioPolicy(audioControl);
        int r = mAudioManager.registerAudioPolicy(audioPolicy);
        if (r != AudioManager.SUCCESS) {
            throw new RuntimeException("registerAudioPolicy failed " + r);
        }
        mAudioPolicy = audioPolicy;
    }
```

这部分代码逻辑不是很复杂，只是将AudioControl的实例传给了getDynamicAudioPolicy()方法，继续分析getDynamicAudioPolicy(),代码如下：

```java
    @Nullable
    private AudioPolicy getDynamicAudioPolicy(@NonNull IAudioControl audioControl) {

        AudioPolicy.Builder builder = new AudioPolicy.Builder(mContext);
        builder.setLooper(Looper.getMainLooper());

        AudioDeviceInfo[] deviceInfos = mAudioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);
        if (deviceInfos.length == 0) {
            Log.e(CarLog.TAG_AUDIO, "getDynamicAudioPolicy, no output device available, ignore");
            return null;
        }

        for (AudioDeviceInfo info : deviceInfos) {
            Log.v(CarLog.TAG_AUDIO, String.format("output id=%d address=%s type=%s",
                    info.getId(), info.getAddress(), info.getType()));
            if (info.getType() == AudioDeviceInfo.TYPE_BUS) {
                final CarAudioDeviceInfo carInfo = new CarAudioDeviceInfo(info);

                if (carInfo.getBusNumber() >= 0) {
                    mCarAudioDeviceInfos.put(carInfo.getBusNumber(), carInfo);
                    Log.i(CarLog.TAG_AUDIO, "Valid bus found " + carInfo);
                }
            }
        }

        try {
            for (int contextNumber : CONTEXT_NUMBERS) {

                int busNumber = audioControl.getBusForContext(contextNumber);
                mContextToBus.put(contextNumber, busNumber);
                CarAudioDeviceInfo info = mCarAudioDeviceInfos.get(busNumber);
                if (info == null) {
                    Log.w(CarLog.TAG_AUDIO, "No bus configured for context: " + contextNumber);
                }
            }
        } catch (RemoteException e) {
            Log.e(CarLog.TAG_AUDIO, "Error mapping context to physical bus", e);
        }

        for (int i = 0; i < mCarAudioDeviceInfos.size(); i++) {

            int busNumber = mCarAudioDeviceInfos.keyAt(i);
            boolean hasContext = false;
            CarAudioDeviceInfo info = mCarAudioDeviceInfos.valueAt(i);
            AudioFormat mixFormat = new AudioFormat.Builder()
                    .setSampleRate(info.getSampleRate())
                    .setEncoding(info.getEncodingFormat())
                    .setChannelMask(info.getChannelCount())
                    .build();
            AudioMixingRule.Builder mixingRuleBuilder = new AudioMixingRule.Builder();
            for (int j = 0; j < mContextToBus.size(); j++) {

                if (mContextToBus.valueAt(j) == busNumber) {
                    hasContext = true;

                    int contextNumber = mContextToBus.keyAt(j);

                    int[] usages = getUsagesForContext(contextNumber);
                    for (int usage : usages) {

                        mixingRuleBuilder.addRule(
                                new AudioAttributes.Builder().setUsage(usage).build(),
                                AudioMixingRule.RULE_MATCH_ATTRIBUTE_USAGE);
                    }
                    Log.i(CarLog.TAG_AUDIO, "Bus number: " + busNumber
                            + " contextNumber: " + contextNumber
                            + " sampleRate: " + info.getSampleRate()
                            + " channels: " + info.getChannelCount()
                            + " usages: " + Arrays.toString(usages));
                }
            }

            if (hasContext) {

                AudioMix audioMix = new AudioMix.Builder(mixingRuleBuilder.build())
                        .setFormat(mixFormat)
                        .setDevice(info.getAudioDeviceInfo())
                        .setRouteFlags(AudioMix.ROUTE_FLAG_RENDER)
                        .build();

                builder.addMix(audioMix);
            }
        }

        builder.setAudioPolicyVolumeCallback(mAudioPolicyVolumeCallback);

        return builder.build();
    }
```

上边代码有些长，但是核心的东西。我们把AudioAttribute和AUDIO_DEVICE_OUT_BUS映射起来，存入AudioMix并通过mAudioManager.registerAudioPolicy(audioPolicy)注册下去，最终会在Audio PolicyManagerj进行路由策略时优先对应我们注册下来的这些策略。

我们做Android原生的定制的时候，我们知道新增一个路由策略，我们要从java层新追加定义AudioStream开始，一步一步通过AudioTrack到jni到AudioPolicy，到Engine的strategy。我们全部都要定义，对于初学是难度很大的，因为每一步的逻辑都是需要完全理解的。而AUDIO_DEVICE_OUT_BUS的形式会大大缩短我们的定制风险和难度。当然并不是每一种方案都是完美的，比如基于AUDIO_DEVICE_OUT_BUS的这种策略我们可以满足不同声音不同通路输出的需求，但如果在想通过软件来调节音量可能有些情况就不能满足了，因此我们还需要根据具体需求去做具体处理。后面我们会继续分析AUDIO_DEVICE_OUT_BUS的策略修改与定制
