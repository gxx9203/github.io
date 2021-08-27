---
link: https://blog.csdn.net/l328873524/article/details/105131715
title: Android10.0Auidio之MediaPlayer（四）
description: 前言之前说了MediaPlayer如何从java层到jni，以及jin如何callback回调到java，今天继续看看native层的mediaplayer又做了什么。正文先说下路径位于frameworks/av/media/libmedia/mediaplayer.cpp，我们先从mediaplayer的构造跟析构函数说起MediaPlayer::MediaPlayer(){    ...
keywords: Android10.0Auidio之MediaPlayer（四）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-03-26T17:18:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=24 sentences=22, words=435
---
之前说了MediaPlayer如何从java层到jni，以及jin如何callback回调到java，今天继续看看native层的mediaplayer又做了什么。

先说下路径位于frameworks/av/media/libmedia/mediaplayer.cpp，我们先从mediaplayer的构造跟析构函数说起

```cpp
MediaPlayer::MediaPlayer()
{
    ALOGV("constructor");
    mListener = NULL;
    mCookie = NULL;
    mStreamType = AUDIO_STREAM_MUSIC;
    mAudioAttributesParcel = NULL;
    mCurrentPosition = -1;
    mCurrentSeekMode = MediaPlayerSeekMode::SEEK_PREVIOUS_SYNC;
    mSeekPosition = -1;
    mSeekMode = MediaPlayerSeekMode::SEEK_PREVIOUS_SYNC;
    mCurrentState = MEDIA_PLAYER_IDLE;
    mPrepareSync = false;
    mPrepareStatus = NO_ERROR;
    mLoop = false;
    mLeftVolume = mRightVolume = 1.0;
    mVideoWidth = mVideoHeight = 0;
    mLockThreadId = 0;
    mAudioSessionId = (audio_session_t) AudioSystem::newAudioUniqueId(AUDIO_UNIQUE_ID_USE_SESSION);
    AudioSystem::acquireAudioSessionId(mAudioSessionId, -1);
    mSendLevel = 0;
    mRetransmitEndpointValid = false;
}

MediaPlayer::~MediaPlayer()
{
    ALOGV("destructor");
    if (mAudioAttributesParcel != NULL) {
        delete mAudioAttributesParcel;
        mAudioAttributesParcel = NULL;
    }
    AudioSystem::releaseAudioSessionId(mAudioSessionId, -1);
    disconnect();
    IPCThreadState::self()->flushCommands();
}
```

构造函数初始化了好多参数，等具体使用的时候我们再一一细说，析构呢有一个disconnect(),这是做什么的呢

```cpp
void MediaPlayer::disconnect()
{
    ALOGV("disconnect");
    sp<IMediaPlayer> p;
    {
        Mutex::Autolock _l(mLock);
        p = mPlayer;
        mPlayer.clear();
    }

    if (p != 0) {
        p->disconnect();
    }
}
```

mPlayer是啥呢？源码先放在这，后续分析，从mediaplayer的构造函数，我们大体知道貌似初始化了好多参数，但不清楚具体都做了什么。我们记得之前我们在分析jni的时候有个 mp->setListener(listener);这个listener是一个jni的JNIMediaPlayerListener，我们回到jni在看下，原来

```cpp
JNIMediaPlayerListener: public MediaPlayerListener
```

继承自MediaPlayerListener，通过jni的头文件#include

```cpp
status_t MediaPlayer::setListener(const sp<MediaPlayerListener>& listener)
{
    ALOGV("setListener");
    Mutex::Autolock _l(mLock);
    mListener = listener;
    return NO_ERROR;
}
```

到此native层如何回调到java层的逻辑就彻底清楚了。java层在创建MediaPlayer的时候，native层同时也会对应创建一个native的medaplayer，并在jni中set一个mediaplayerListener下来，这个listener主要作用回调jave层的postEventFromNative方法最终实现整个cllback的逻辑，具体可参照[Android10.0Auidio之MediaPlayer（二）](https://blog.csdn.net/l328873524/article/details/104384177)和[Android10.0Auidio之MediaPlayer （三）](https://blog.csdn.net/l328873524/article/details/104158291)
继续分析，在看下setDataSource吧，由于setDataSource的函数很多，这里只说一个

```cpp
status_t MediaPlayer::setDataSource(int fd, int64_t offset, int64_t length)
{
    ALOGV("setDataSource(%d, %" PRId64 ", %" PRId64 ")", fd, offset, length);
    status_t err = UNKNOWN_ERROR;
    const sp<IMediaPlayerService> service(getMediaPlayerService());
    if (service != 0) {
        sp<IMediaPlayer> player(service->create(this, mAudioSessionId));
        if ((NO_ERROR != doSetRetransmitEndpoint(player)) ||
            (NO_ERROR != player->setDataSource(fd, offset, length))) {
            player.clear();
        }
        err = attachNewPlayer(player);
    }
    return err;
}
```

这里先来分析下const sp service(getMediaPlayerService());其实大概也可以猜到获取mediaplayer的service嘛，但是具体怎么实现的呢？
我们知道mediaplayer继承自IMediaDeathNotifier，

```cpp
IMediaDeathNotifier::getMediaPlayerService()
{
    ALOGV("getMediaPlayerService");
    Mutex::Autolock _l(sServiceLock);
    if (sMediaPlayerService == 0) {
        sp<IServiceManager> sm = defaultServiceManager();
        sp<IBinder> binder;
        do {
            binder = sm->getService(String16("media.player"));
            if (binder != 0) {
                break;
            }
            ALOGW("Media player service not published, waiting...");
            usleep(500000);
        } while (true);

        if (sDeathNotifier == NULL) {
            sDeathNotifier = new DeathNotifier();
        }
        binder->linkToDeath(sDeathNotifier);
        sMediaPlayerService = interface_cast<IMediaPlayerService>(binder);
    }
    ALOGE_IF(sMediaPlayerService == 0, "no media player service!?");
    return sMediaPlayerService;
}
```

简单扫一眼，等说到mediaplayerservice的时候在具体说这块，这里不多说了，大概明白是个binder通信就可以了，拿到了service后先执行了sp player(service->create(this, mAudioSessionId));
很简单主要是拿这个服务的binder对象，然后调用service中的setDataSource（），然后attachNewPlayer(player)，最终将结果返给jni，最终回调到java层。
这里先简单说下attachNewPlayer函数

```cpp
status_t MediaPlayer::attachNewPlayer(const sp<IMediaPlayer>& player)
{
    status_t err = UNKNOWN_ERROR;
    sp<IMediaPlayer> p;
    {
        Mutex::Autolock _l(mLock);

        if ( !( (mCurrentState & MEDIA_PLAYER_IDLE) ||
                (mCurrentState == MEDIA_PLAYER_STATE_ERROR ) ) ) {
            ALOGE("attachNewPlayer called in state %d", mCurrentState);
            return INVALID_OPERATION;
        }

        clear_l();
        p = mPlayer;
        mPlayer = player;
        if (player != 0) {
            mCurrentState = MEDIA_PLAYER_INITIALIZED;
            err = NO_ERROR;
        } else {
            ALOGE("Unable to create media player");
        }
    }

    if (p != 0) {
        p->disconnect();
    }

    return err;
}
```

代码不是很复杂，基本就是在client端与service端通信，主要通过这个mPlayer。

今天说的好多都是把前边的串联起来了，native层的mediaplayer构造的时候初始化了mListener主要用作向java层传递callback用，而native层的mediaplayer
最终通过binder与mediaplayerservice通信，其实这里有一个参数mAudioSessionId我们在setDataSource和构造函数中都看到了，这里没有具体说抽时间单独聊一下这个，因为不仅mediaplayer，包括audiotrack以及audiopolicy很多地方都用到了mAudioSessionId这个东西。我觉得还是有必要单独细说一下的。
