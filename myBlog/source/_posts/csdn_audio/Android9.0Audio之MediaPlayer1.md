---
link: https://blog.csdn.net/l328873524/article/details/103051584
title: Android9.0Auidio之MediaPlayer（一）
description: 2019年就要结束了，回首碌碌无为的一年，对于没有好文凭和好背景（大厂工作经验）的大龄程序员，又背负着各种贷款和养家糊口的压力，总觉得要有点作为，突然有个想法，从application到framework到hal整理下整个audio发声的时序，虽然路慢慢而修远兮，吾将上下而求索。干就得了...
keywords: Android9.0Auidio之MediaPlayer（一）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2019-11-18T15:59:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=124 sentences=67, words=861
---
2019年就要结束了，回首碌碌无为的一年，对于没有好文凭和好背景（大厂工作经验）的大龄程序员，又背负着各种贷款和养家糊口的压力，总觉得要做点什么，突然有个想法，从application到framework到hal整理下整个audio源码解析，路慢慢而修远兮，吾将上下而求索。话不多说，干就得了

### 正文

android关于媒体播放的方式主要有三种，我们通过一些资料以及官方文档大概都了解MediaPlayer、SoundPool、以及AudioTrack。或者他们的区别和使用场景，我们也都很熟悉，但无论哪一种方式，又是如何将声音一步一步播放出来最终人耳可以感受到的呢？今天先来分析下MediaPlayer。

###### MediaPlayer 状态图

说API之前先看下MediaPlayer的状态转化图：
![](https://img-blog.csdnimg.cn/20191114235555786.gif)
这张图完全说明了MediaPlayer的各个状态的转化逻辑，哪些状态可以来回转化，哪些状态不可以，这个图非常重要。

###### <a name="mediaplayer_9">;</a>  MediaPlayer的初始化

这种通过构造函数来初始化可能是我们使用最多的了，那么就看看初始化都做了什么

```java
/frameworks/base/media/java/android/media/MediaPlayer.java
    public MediaPlayer() {

        super(new AudioAttributes.Builder().build(),
                AudioPlaybackConfiguration.PLAYER_TYPE_JAM_MEDIAPLAYER);

        Looper looper;

        if ((looper = Looper.myLooper()) != null) {

            mEventHandler = new EventHandler(this, looper);
        } else if ((looper = Looper.getMainLooper()) != null) {
            mEventHandler = new EventHandler(this, looper);
        } else {
            mEventHandler = null;
        }

        mTimeProvider = new TimeProvider(this);

        mOpenSubtitleSources = new Vector<InputStream>();

        native_setup(new WeakReference<MediaPlayer>(this));

        baseRegisterPlayer();
    }
```

初始化过程中，主要用native_setup()通过jni同步在native层初始化对应mediaplayer，以及baseRegisterPlayer(),这是父类PlayerBase中的方法，具体做了什么呢

```java
    protected void baseRegisterPlayer() {
        int newPiid = AudioPlaybackConfiguration.PLAYER_PIID_INVALID;

        IBinder b = ServiceManager.getService(Context.APP_OPS_SERVICE);
        mAppOps = IAppOpsService.Stub.asInterface(b);

        updateAppOpsPlayAudio();

        mAppOpsCallback = new IAppOpsCallbackWrapper(this);
        try {

            mAppOps.startWatchingMode(AppOpsManager.OP_PLAY_AUDIO,
                    ActivityThread.currentPackageName(), mAppOpsCallback);
        } catch (RemoteException e) {
            mHasAppOpsPlayAudio = false;
        }
        try {

            newPiid = getService().trackPlayer(
                    new PlayerIdCard(mImplType, mAttributes, new IPlayerWrapper(this)));
        } catch (RemoteException e) {
            Log.e(TAG, "Error talking to audio service, player will not be tracked", e);
        }
        mPlayerIId = newPiid;
    }
```

这里主要是一个内部权限的处理，以及通知给AudioService trackPlayer(),其实MediaPlayer的初始化方式很多，比如create(),MediaPlayer的create方法，为我们提供了各种参数的支持，其实create方法只不过是把我们new Mediaplayer，以及setAudioAttributes,setDataSource，等一系列初始化操作，全都替我们弄好了，这里简单看几个create方法的源码：

```java

    public static MediaPlayer create(Context context, Uri uri, SurfaceHolder holder,
            AudioAttributes audioAttributes, int audioSessionId) {

        try {

            MediaPlayer mp = new MediaPlayer();
            final AudioAttributes aa = audioAttributes != null ? audioAttributes :
                new AudioAttributes.Builder().build();
            mp.setAudioAttributes(aa);
            mp.setAudioSessionId(audioSessionId);
            mp.setDataSource(context, uri);
            if (holder != null) {
                mp.setDisplay(holder);
            }
            mp.prepare();
            return mp;
        } catch (IOException ex) {
            Log.d(TAG, "create failed:", ex);

        } catch (IllegalArgumentException ex) {
            Log.d(TAG, "create failed:", ex);

        } catch (SecurityException ex) {
            Log.d(TAG, "create failed:", ex);

        }

        return null;
    }
```

不管我们自己new MediaPlayer，然后设置各种参数也好，直接通过create的方式初始化也罢，最终结果是一样的。

###### setAudioAttributes()

说setAudioAttributes()先说下setAudioStreamType()，源码如下：

```java

    public void setAudioStreamType(int streamtype) {

        deprecateStreamTypeForPlayback(streamtype, "MediaPlayer", "setAudioStreamType()");

        baseUpdateAudioAttributes(
                new AudioAttributes.Builder().setInternalLegacyStreamType(streamtype).build());

        _setAudioStreamType(streamtype);

        mStreamType = streamtype;
    }
```

然后再说setAudioAttributes()

```java
    public void setAudioAttributes(AudioAttributes attributes) throws IllegalArgumentException {
        if (attributes == null) {
            final String msg = "Cannot set AudioAttributes to null";
            throw new IllegalArgumentException(msg);
        }

        baseUpdateAudioAttributes(attributes);

        mUsage = attributes.getUsage();

        mBypassInterruptionPolicy = (attributes.getAllFlags()
                & AudioAttributes.FLAG_BYPASS_INTERRUPTION_POLICY) != 0;
        Parcel pattributes = Parcel.obtain();
        attributes.writeToParcel(pattributes, AudioAttributes.FLATTEN_TAGS);

        setParameter(KEY_PARAMETER_AUDIO_ATTRIBUTES, pattributes);
        pattributes.recycle();
    }
```

通过setAudioStreamType注释发现谷歌不建议使用setAudioAttributes，但自己内部create的方法调用的都是setAudioAttributes，有点意思，个人建议还是使用setAudioAttributes这种方式（谷歌不建议个人怀疑只是为了排除STREAM_ACCESSIBILITY）setAudioAttributes因此这种方法在车载开发中，尤其使用了 AUDIO_DEVICE_OUT_BUS时，屡试不爽，因为AUDIO_DEVICE_OUT_BUS就是通过AUdioAttributes的usage处理的而不是streamType。

###### setVolume()

这个使用的不是很多，因为AudioManager有专门的调音接口，代码比较简单。

```java

    public void setVolume(float leftVolume, float rightVolume) {

        baseSetVolume(leftVolume, rightVolume);
    }
```

###### setLooping()

设置播放模式 循环播放。

```java

	public native void setLooping(boolean looping);
```

###### setSurface()/setDisplay()

关于播放视频时对于surface和surfaceHolder的设置

```java

    public void setSurface(Surface surface) {
        if (mScreenOnWhilePlaying && surface != null) {
            Log.w(TAG, "setScreenOnWhilePlaying(true) is ineffective for Surface");
        }
        mSurfaceHolder = null;
        _setVideoSurface(surface);

        updateSurfaceScreenOn();
    }

    public void setDisplay(SurfaceHolder sh) {
        mSurfaceHolder = sh;
        Surface surface;
        if (sh != null) {
            surface = sh.getSurface();
        } else {
            surface = null;
        }
        _setVideoSurface(surface);
        updateSurfaceScreenOn();
    }
```

两个方法都调用了updateSurfaceScreenOn，简单看下逻辑。

```java
    private void updateSurfaceScreenOn() {
        if (mSurfaceHolder != null) {

            mSurfaceHolder.setKeepScreenOn(mScreenOnWhilePlaying && mStayAwake);
        }
    }
```

###### getCurrentPosition ()

```java

    public native int getCurrentPosition();
```

###### getDuration()

```java

    public native int getDuration();
```

###### isPlaying()

关于isPlaying的使用后续会继续说明

```java

	public native boolean isPlaying();
```

###### reset()

终于可以说到这个状态图了，就先从reset方法说起。

```java
    public void reset() {

        mSelectedSubtitleTrackIndex = -1;
        synchronized(mOpenSubtitleSources) {
            for (final InputStream is: mOpenSubtitleSources) {
                try {
                    is.close();
                } catch (IOException e) {
                }
            }
            mOpenSubtitleSources.clear();
        }
        if (mSubtitleController != null) {
            mSubtitleController.reset();
        }

        if (mTimeProvider != null) {
            mTimeProvider.close();
            mTimeProvider = null;
        }

        stayAwake(false);

        _reset();

        if (mEventHandler != null) {
            mEventHandler.removeCallbacksAndMessages(null);
        }

        synchronized (mIndexTrackPairs) {
            mIndexTrackPairs.clear();
            mInbandTrackIndices.clear();
        };

        resetDrmState();
    }
```

###### setDataSource()

setDataSource这里不多说了，支持各种参数如文件的 path的 uri的以及资源文件的，具体怎么用百度也是一堆堆的。

###### prepare()

```java
    public void prepare() throws IOException, IllegalStateException {

        _prepare();

        scanInternalSubtitleTracks();

        synchronized (mDrmLock) {
            mDrmInfoResolved = true;
        }
    }
```

还有一个prepareAsync(),异步的prepare需要通过setOnPreparedListener来监听prepare的完成，当收到onPrepared()回调时，便可以开始播放了。

###### start()

start的逻辑不是很复杂

```java
    public void start() throws IllegalStateException {

        final int delay = getStartDelayMs();

        if (delay == 0) {
            startImpl();
        } else {

            new Thread() {
                public void run() {
                    try {
                        Thread.sleep(delay);
                    } catch (InterruptedException e) {
                        e.printStackTrace();
                    }
                    baseSetStartDelayMs(0);
                    try {
                        startImpl();
                    } catch (IllegalStateException e) {

                    }
                }
            }.start();
        }
    }

    private void startImpl() {
        baseStart();
        stayAwake(true);
        _start();
    }
```

关于baseStart中只关注 如下两行代码即可

```java
mState = AudioPlaybackConfiguration.PLAYER_STATE_STARTED;
getService().playerEvent(mPlayerIId, mState);
```

把播放状态传递给了AudioService，包括pause的stop的也都是这么处理的。

###### pause()

```java
    public void pause() throws IllegalStateException {

        stayAwake(false);

        _pause();

        basePause();
    }
```

###### stop()

```java
    public void stop() throws IllegalStateException {

        stayAwake(false);

        _stop();

        baseStop();
    }
```

###### release()

```java
    public void release() {
        baseRelease();
        stayAwake(false);
        updateSurfaceScreenOn();
        mOnPreparedListener = null;
        mOnBufferingUpdateListener = null;
        mOnCompletionListener = null;
        mOnSeekCompleteListener = null;
        mOnErrorListener = null;
        mOnInfoListener = null;
        mOnVideoSizeChangedListener = null;
        mOnTimedTextListener = null;
        if (mTimeProvider != null) {
            mTimeProvider.close();
            mTimeProvider = null;
        }
        mOnSubtitleDataListener = null;

        mOnDrmConfigHelper = null;
        mOnDrmInfoHandlerDelegate = null;
        mOnDrmPreparedHandlerDelegate = null;
        resetDrmState();

        _release();
    }
```

其实release后我们发现基本所有的设置都被清楚了，通过状态图也能看出，release后基本mediaplayer就不能在用了。因此只有当我们在退出播放，或者不需要在使用mediaplayer的时候才会调用此方法。

###### 其他

mediaplayer还有一些其他API这里就不一一列举了，常用的listener还有setOnCompletionListener以及seErrorListener，如果两个都存在，在发生error的时候，CompletionListener是收不到回调的，因为代码逻辑处理只回调error的listener。

###### 最后

关于MediaPlayer的源码API就说这么多，关于MediaPlayer字幕以及MediaPlayer与AudioService的交互，以后抽时间在整理下，下篇将研究下SoundPool的源码API，以上有说的不准确的地方，还望各位大佬多多指点~。
