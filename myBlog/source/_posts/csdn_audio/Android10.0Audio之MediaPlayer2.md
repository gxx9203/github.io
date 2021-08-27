---
link: https://blog.csdn.net/l328873524/article/details/104384177
title: Android10.0Auidio之MediaPlayer（二）
description: 不知不觉就2020年了，不知不觉Android就到了10.0了，不知不觉又TM好久没更了，不知不觉新冠病毒还是遥遥无期，考虑了下后续还是基于10.0来继续分析吧。MediaPlayer的java层API的使用以及说明网上还是很多的，如果深究其原理呢，会发现最终都调了native XXX方法，其实这就调到了jnistatic {           System.loadLibrary("me...
keywords: Android10.0Auidio之MediaPlayer（二）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-02-24T15:32:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=40 sentences=35, words=902
---
不知不觉就2020年了，不知不觉Android就到了10.0了，不知不觉又TM好久没更了，不知不觉新冠病毒还是遥遥无期，考虑了下后续还是基于10.0来继续分析吧。
MediaPlayer的java层API的使用以及说明网上还是很多的，如果深究其原理呢，会发现最终都调了native XXX方法，其实这就调到了jni

```java
static {
        System.loadLibrary("media_jni");
        native_init();
      }
```

这里调到了media_jin,在frameworks/base/media/jni/android_media_MediaPlayer.cpp 中

```cpp
static const JNINativeMethod gMethods[] = {
    {
        "nativeSetDataSource",
        "(Landroid/os/IBinder;Ljava/lang/String;[Ljava/lang/String;"
        "[Ljava/lang/String;)V",
        (void *)android_media_MediaPlayer_setDataSourceAndHeaders
    },

    {"_setDataSource",      "(Ljava/io/FileDescriptor;JJ)V",    (void *)android_media_MediaPlayer_setDataSourceFD},
    {"_setDataSource",      "(Landroid/media/MediaDataSource;)V",(void *)android_media_MediaPlayer_setDataSourceCallback },
    {"_setVideoSurface",    "(Landroid/view/Surface;)V",        (void *)android_media_MediaPlayer_setVideoSurface},
    {"_prepare",            "()V",                              (void *)android_media_MediaPlayer_prepare},
    {"prepareAsync",        "()V",                              (void *)android_media_MediaPlayer_prepareAsync},
    {"_start",              "()V",                              (void *)android_media_MediaPlayer_start},
    {"_stop",               "()V",                              (void *)android_media_MediaPlayer_stop},
    {"getVideoWidth",       "()I",                              (void *)android_media_MediaPlayer_getVideoWidth},
    {"getVideoHeight",      "()I",                              (void *)android_media_MediaPlayer_getVideoHeight},
    {"native_getMetrics",   "()Landroid/os/PersistableBundle;", (void *)android_media_MediaPlayer_native_getMetrics},
    {"setPlaybackParams", "(Landroid/media/PlaybackParams;)V", (void *)android_media_MediaPlayer_setPlaybackParams},
    {"getPlaybackParams", "()Landroid/media/PlaybackParams;", (void *)android_media_MediaPlayer_getPlaybackParams},
    {"setSyncParams",     "(Landroid/media/SyncParams;)V",  (void *)android_media_MediaPlayer_setSyncParams},
    {"getSyncParams",     "()Landroid/media/SyncParams;",   (void *)android_media_MediaPlayer_getSyncParams},
    {"_seekTo",             "(JI)V",                            (void *)android_media_MediaPlayer_seekTo},
    {"_notifyAt",           "(J)V",                             (void *)android_media_MediaPlayer_notifyAt},
    {"_pause",              "()V",                              (void *)android_media_MediaPlayer_pause},
    {"isPlaying",           "()Z",                              (void *)android_media_MediaPlayer_isPlaying},
    {"getCurrentPosition",  "()I",                              (void *)android_media_MediaPlayer_getCurrentPosition},
    {"getDuration",         "()I",                              (void *)android_media_MediaPlayer_getDuration},
    {"_release",            "()V",                              (void *)android_media_MediaPlayer_release},
    {"_reset",              "()V",                              (void *)android_media_MediaPlayer_reset},
    {"_setAudioStreamType", "(I)V",                             (void *)android_media_MediaPlayer_setAudioStreamType},
    {"_getAudioStreamType", "()I",                              (void *)android_media_MediaPlayer_getAudioStreamType},
    {"setParameter",        "(ILandroid/os/Parcel;)Z",          (void *)android_media_MediaPlayer_setParameter},
    {"setLooping",          "(Z)V",                             (void *)android_media_MediaPlayer_setLooping},
    {"isLooping",           "()Z",                              (void *)android_media_MediaPlayer_isLooping},
    {"_setVolume",          "(FF)V",                            (void *)android_media_MediaPlayer_setVolume},
    {"native_invoke",       "(Landroid/os/Parcel;Landroid/os/Parcel;)I",(void *)android_media_MediaPlayer_invoke},
    {"native_setMetadataFilter", "(Landroid/os/Parcel;)I",      (void *)android_media_MediaPlayer_setMetadataFilter},
    {"native_getMetadata", "(ZZLandroid/os/Parcel;)Z",          (void *)android_media_MediaPlayer_getMetadata},
    {"native_init",         "()V",                              (void *)android_media_MediaPlayer_native_init},
    {"native_setup",        "(Ljava/lang/Object;)V",            (void *)android_media_MediaPlayer_native_setup},
    {"native_finalize",     "()V",                              (void *)android_media_MediaPlayer_native_finalize},
    {"getAudioSessionId",   "()I",                              (void *)android_media_MediaPlayer_get_audio_session_id},
    {"setAudioSessionId",   "(I)V",                             (void *)android_media_MediaPlayer_set_audio_session_id},
    {"_setAuxEffectSendLevel", "(F)V",                          (void *)android_media_MediaPlayer_setAuxEffectSendLevel},
    {"attachAuxEffect",     "(I)V",                             (void *)android_media_MediaPlayer_attachAuxEffect},
    {"native_pullBatteryData", "(Landroid/os/Parcel;)I",        (void *)android_media_MediaPlayer_pullBatteryData},
    {"native_setRetransmitEndpoint", "(Ljava/lang/String;I)I",  (void *)android_media_MediaPlayer_setRetransmitEndpoint},
    {"setNextMediaPlayer",  "(Landroid/media/MediaPlayer;)V",   (void *)android_media_MediaPlayer_setNextMediaPlayer},
    {"native_applyVolumeShaper",
                            "(Landroid/media/VolumeShaper$Configuration;Landroid/media/VolumeShaper$Operation;)I",
                                                                (void *)android_media_MediaPlayer_applyVolumeShaper},
    {"native_getVolumeShaperState",
                            "(I)Landroid/media/VolumeShaper$State;",
                                                                (void *)android_media_MediaPlayer_getVolumeShaperState},

    { "_prepareDrm", "([B[B)V",                                 (void *)android_media_MediaPlayer_prepareDrm },
    { "_releaseDrm", "()V",                                     (void *)android_media_MediaPlayer_releaseDrm },

    {"native_setOutputDevice", "(I)Z",                          (void *)android_media_MediaPlayer_setOutputDevice},
    {"native_getRoutedDeviceId", "()I",                         (void *)android_media_MediaPlayer_getRoutedDeviceId},
    {"native_enableDeviceCallback", "(Z)V",                     (void *)android_media_MediaPlayer_enableDeviceCallback},
};
```

这里我列了所有java调下来的native方法。我们简单分析一个native_init对应到jin里是android_media_Mediaplayer_native_init

```cpp
static void
android_media_MediaPlayer_native_init(JNIEnv *env)
{
    jclass clazz;

    clazz = env->FindClass("android/media/MediaPlayer");
    if (clazz == NULL) {
        return;
    }

    fields.context = env->GetFieldID(clazz, "mNativeContext", "J");
    if (fields.context == NULL) {
        return;
    }

    fields.post_event = env->GetStaticMethodID(clazz, "postEventFromNative",
                                               "(Ljava/lang/Object;IIILjava/lang/Object;)V");
    if (fields.post_event == NULL) {
        return;
    }

    fields.surface_texture = env->GetFieldID(clazz, "mNativeSurfaceTexture", "J");
    if (fields.surface_texture == NULL) {
        return;
    }

    env->DeleteLocalRef(clazz);

    clazz = env->FindClass("android/net/ProxyInfo");
    if (clazz == NULL) {
        return;
    }

    fields.proxyConfigGetHost =
        env->GetMethodID(clazz, "getHost", "()Ljava/lang/String;");

    fields.proxyConfigGetPort =
        env->GetMethodID(clazz, "getPort", "()I");

    fields.proxyConfigGetExclusionList =
        env->GetMethodID(clazz, "getExclusionListAsString", "()Ljava/lang/String;");

    env->DeleteLocalRef(clazz);

    FIND_CLASS(clazz, "android/media/MediaDrm$MediaDrmStateException");
    if (clazz) {
        GET_METHOD_ID(gStateExceptionFields.init, clazz, "", "(ILjava/lang/String;)V");
        gStateExceptionFields.classId = static_cast<jclass>(env->NewGlobalRef(clazz));

        env->DeleteLocalRef(clazz);
    } else {
        ALOGE("JNI android_media_MediaPlayer_native_init couldn't "
              "get clazz android/media/MediaDrm$MediaDrmStateException");
    }

    gPlaybackParamsFields.init(env);
    gSyncParamsFields.init(env);
    gVolumeShaperFields.init(env);
}
```

获取一些java层的变量以及方法，这里之分析了fields.context和fields.post_event，一个指向java层的变量一个指向Java层的函数。后面的在使用到时在具体在分析。
还记得在new MediaPlayer创建对象时，调用了native_setup。

```cpp
static void
android_media_MediaPlayer_native_setup(JNIEnv *env, jobject thiz, jobject weak_this)
{
    ALOGV("native_setup");

    sp<MediaPlayer> mp = new MediaPlayer();
    if (mp == NULL) {
        jniThrowException(env, "java/lang/RuntimeException", "Out of memory");
        return;
    }

    sp<JNIMediaPlayerListener> listener = new JNIMediaPlayerListener(env, thiz, weak_this);
    mp->setListener(listener);

    setMediaPlayer(env, thiz, mp);
}
```

继续分析这个setMediaPlayer

```cpp
static sp<MediaPlayer> setMediaPlayer(JNIEnv* env, jobject thiz, const sp<MediaPlayer>& player)
{
    Mutex::Autolock l(sLock);

    sp<MediaPlayer> old = (MediaPlayer*)env->GetLongField(thiz, fields.context);
    if (player.get()) {
        player->incStrong((void*)setMediaPlayer);
    }
    if (old != 0) {
        old->decStrong((void*)setMediaPlayer);
    }
    env->SetLongField(thiz, fields.context, (jlong)player.get());
    return old;
}
```

这个方法的作用就时把创建的native Mediaplayer赋值给到java层的MediaPlayer的mNativeContex了
最后再看下JNIMediaPlayerListener，其实就一个回调notify

```cpp
void JNIMediaPlayerListener::notify(int msg, int ext1, int ext2, const Parcel *obj)
{
    JNIEnv *env = AndroidRuntime::getJNIEnv();
    if (obj && obj->dataSize() > 0) {
        jobject jParcel = createJavaParcelObject(env);
        if (jParcel != NULL) {
            Parcel* nativeParcel = parcelForJavaObject(env, jParcel);
            nativeParcel->setData(obj->data(), obj->dataSize());

            env->CallStaticVoidMethod(mClass, fields.post_event, mObject,
                    msg, ext1, ext2, jParcel);
            env->DeleteLocalRef(jParcel);
        }
    } else {
        env->CallStaticVoidMethod(mClass, fields.post_event, mObject,
                msg, ext1, ext2, NULL);
    }
    if (env->ExceptionCheck()) {
        ALOGW("An exception occurred while notifying an event.");
        LOGW_EX(env);
        env->ExceptionClear();
    }
}
```

也就是native层的callback最终会通过postEventFromNative返回给java层，好了，我们在看下刚才创建的native的nediaplayer，代码位于/frameworks/av/media/libmedia/mediaplayer.cpp ，

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
```

一堆参数的初始化，这里不一一说明了，等用到时在具体细说。
在看下刚才的setListener

```cpp
status_t MediaPlayer::setListener(const sp<MediaPlayerListener>& listener)
{
    ALOGV("setListener");
    Mutex::Autolock _l(mLock);
    mListener = listener;
    return NO_ERROR;
}
```

也是非常简单，这里mListener就赋值了。

从java层创建MediaPlayer开始主要做了几件事：
1.java层调到jni并创建native层的mediaplayer
2.把native层的mediaplayer赋值给java层的mNativeContex
3.在native层注册listener并绑定到java层的postEventFromNative

下篇我们就从MediaPlayer的setDataSource开始，看看java层调用setDataSource后，native层都做了什么
