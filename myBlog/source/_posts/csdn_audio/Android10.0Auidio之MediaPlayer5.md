---
link: https://blog.csdn.net/l328873524/article/details/105520411
title: Android10.0Auidio之MediaPlayer（五）
description: 前言前边分析了MediaPlayer从java通过jni到native层的过程，其实mediaplayer的真正的逻辑存在是在mediaPlayerservice中处理的，那么今天我们就从源码看下mediaplayer的初始化过程正文mediaplayerservice通过mediaserver.rc启动，我们先看下man函数，源码位置/frameworks/av/media/mediase...
keywords: Android10.0Auidio之MediaPlayer（五）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-17T16:35:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=77 sentences=64, words=1239
---
前边分析了MediaPlayer从java通过jni到native层的过程，其实mediaplayer的真正的逻辑存在是在mediaPlayerService中处理的，那么今天我们就从源码看下mediaplayerService的初始化过程

MediaPlayerService通过mediaserver.rc启动，我们先看下man函数，源码位置/frameworks/av/media/mediaserver/

```cpp
int main(int argc __unused, char **argv __unused)
{
    signal(SIGPIPE, SIG_IGN);

    sp<ProcessState> proc(ProcessState::self());
    sp<IServiceManager> sm(defaultServiceManager());
    ALOGI("ServiceManager: %p", sm.get());
    AIcu_initializeIcuOrDie();

    MediaPlayerService::instantiate();

    ResourceManagerService::instantiate();
    registerExtensions();
    ProcessState::self()->startThreadPool();
    IPCThreadState::self()->joinThreadPool();
}
```

main函数基本就是将MediaPlayerService加到servicemanager中，

```cpp
void MediaPlayerService::instantiate() {
    defaultServiceManager()->addService(
            String16("media.player"), new MediaPlayerService());
}
```

我们继续看它的构造函数

```cpp
MediaPlayerService::MediaPlayerService()
{
    ALOGV("MediaPlayerService created");
    mNextConnId = 1;

    MediaPlayerFactory::registerBuiltinFactories();
}
```

调用了MediaPlayerFactory的registerBuiltinFactories，

```cpp
void MediaPlayerFactory::registerBuiltinFactories() {
    Mutex::Autolock lock_(&sLock);

    if (sInitComplete)
        return;

    IFactory* factory = new NuPlayerFactory();
    if (registerFactory_l(factory, NU_PLAYER) != OK)
        delete factory;
    factory = new TestPlayerFactory();
    if (registerFactory_l(factory, TEST_PLAYER) != OK)
        delete factory;

    sInitComplete = true;
}
```

我们发现只new了两个player分别是NuPlayerFactory和TestPlayerFactory。我们再看下NU_PLAYER和TEST_PLAYER的定义

```cpp
enum player_type {
    STAGEFRIGHT_PLAYER = 3,
    NU_PLAYER = 4,

    TEST_PLAYER = 5,
};
```

只有3个，我们发现是从3开始的，那么说明 1和2应该是被放弃了。这里注释着重说明了TEST_PLAYER的使用场景only in the 'test' and 'eng' builds，创建了两个player后继续registerFactory_l

```cpp
status_t MediaPlayerFactory::registerFactory_l(IFactory* factory,
                                               player_type type) {

    if (NULL == factory) {
        ALOGE("Failed to register MediaPlayerFactory of type %d, factory is"
              " NULL.", type);
        return BAD_VALUE;
    }

    if (sFactoryMap.indexOfKey(type) >= 0) {
        ALOGE("Failed to register MediaPlayerFactory of type %d, type is"
              " already registered.", type);
        return ALREADY_EXISTS;
    }

    if (sFactoryMap.add(type, factory) < 0) {
        ALOGE("Failed to register MediaPlayerFactory of type %d, failed to add"
              " to map.", type);
        return UNKNOWN_ERROR;
    }

    return OK;
}
```

MediaPlayerService的创建到此就结束了，接下来我们在看下mediaplayer中的client的创建过程，我们还记得在[Android10.0Auidio之MediaPlayer（四）](https://blog.csdn.net/l328873524/article/details/105131715)中我们分析setDataSource的过程的时候get了MediaPlayerService然后调用了service->create

```cpp
sp<IMediaPlayer> MediaPlayerService::create(const sp<IMediaPlayerClient>& client,
        audio_session_t audioSessionId)
{
    pid_t pid = IPCThreadState::self()->getCallingPid();
    int32_t connId = android_atomic_inc(&mNextConnId);

    sp<Client> c = new Client(
            this, pid, connId, client, audioSessionId,
            IPCThreadState::self()->getCallingUid());

    ALOGV("Create new client(%d) from pid %d, uid %d, ", connId, pid,
         IPCThreadState::self()->getCallingUid());

    wp<Client> w = c;
    {
        Mutex::Autolock lock(mLock);
        mClients.add(w);
    }
    return c;
}
```

**也就是我们在Mediaplayer的SetDataSource的时候才会在service中创建client**,继续看下new Client的过程

```cpp
MediaPlayerService::Client::Client(
        const sp<MediaPlayerService>& service, pid_t pid,
        int32_t connId, const sp<IMediaPlayerClient>& client,
        audio_session_t audioSessionId, uid_t uid)
{
    ALOGV("Client(%d) constructor", connId);
    mPid = pid;
    mConnId = connId;
    mService = service;
    mClient = client;
    mLoop = false;
    mStatus = NO_INIT;
    mAudioSessionId = audioSessionId;
    mUid = uid;
    mRetransmitEndpointValid = false;
    mAudioAttributes = NULL;

    mListener = new Listener(this);

#if CALLBACK_ANTAGONIZER
    ALOGD("create Antagonizer");
    mAntagonizer = new Antagonizer(mListener);
#endif
}
```

通过Client的构造函数，我们看到又new了一个Listener，这个listener时一个public MediaPlayerBase::Listener主要内部callback用的，后续用到具体说。我们按着setDataSource继续分析MediaPlayerService

```cpp
status_t MediaPlayerService::Client::setDataSource(int fd, int64_t offset, int64_t length)
{
    ALOGV("setDataSource fd=%d (%s), offset=%lld, length=%lld",
            fd, nameForFd(fd).c_str(), (long long) offset, (long long) length);
    struct stat sb;
    int ret = fstat(fd, &sb);
    if (ret != 0) {
        ALOGE("fstat(%d) failed: %d, %s", fd, ret, strerror(errno));
        return UNKNOWN_ERROR;
    }

    ALOGV("st_dev  = %llu", static_cast<unsigned long long>(sb.st_dev));
    ALOGV("st_mode = %u", sb.st_mode);
    ALOGV("st_uid  = %lu", static_cast<unsigned long>(sb.st_uid));
    ALOGV("st_gid  = %lu", static_cast<unsigned long>(sb.st_gid));
    ALOGV("st_size = %llu", static_cast<unsigned long long>(sb.st_size));

    if (offset >= sb.st_size) {
        ALOGE("offset error");
        return UNKNOWN_ERROR;
    }
    if (offset + length > sb.st_size) {
        length = sb.st_size - offset;
        ALOGV("calculated length = %lld", (long long)length);
    }

    player_type playerType = MediaPlayerFactory::getPlayerType(this,
                                                               fd,
                                                               offset,
                                                               length);
    sp<MediaPlayerBase> p = setDataSource_pre(playerType);
    if (p == NULL) {
        return NO_INIT;
    }

    return mStatus = setDataSource_post(p, p->setDataSource(fd, offset, length));
}
```

这里我也是简单分析了其中的一个我们一直分析的setDataSource函数（有多个），通过跑分机制拿到一个NU_PLAYER的type然后setDataSource_pre

```cpp
sp<MediaPlayerBase> MediaPlayerService::Client::setDataSource_pre(
        player_type playerType)
{
    ALOGV("player type = %d", playerType);

    sp<MediaPlayerBase> p = createPlayer(playerType);
    if (p == NULL) {
        return p;
    }

    std::vector<DeathNotifier> deathNotifiers;

    sp<IServiceManager> sm = defaultServiceManager();
    sp<IBinder> binder = sm->getService(String16("media.extractor"));
    if (binder == NULL) {
        ALOGE("extractor service not available");
        return NULL;
    }
    deathNotifiers.emplace_back(
            binder, [l = wp<MediaPlayerBase>(p)]() {
        sp<MediaPlayerBase> listener = l.promote();
        if (listener) {
            ALOGI("media.extractor died. Sending death notification.");
            listener->sendEvent(MEDIA_ERROR, MEDIA_ERROR_SERVER_DIED,
                                MEDIAEXTRACTOR_PROCESS_DEATH);
        } else {
            ALOGW("media.extractor died without a death handler.");
        }
    });

    {
        using ::android::hidl::base::V1_0::IBase;

        {
            sp<IBase> base = ::android::hardware::media::omx::V1_0::
                    IOmx::getService();
            if (base == nullptr) {
                ALOGD("OMX service is not available");
            } else {
                deathNotifiers.emplace_back(
                        base, [l = wp<MediaPlayerBase>(p)]() {
                    sp<MediaPlayerBase> listener = l.promote();
                    if (listener) {
                        ALOGI("OMX service died. "
                              "Sending death notification.");
                        listener->sendEvent(
                                MEDIA_ERROR, MEDIA_ERROR_SERVER_DIED,
                                MEDIACODEC_PROCESS_DEATH);
                    } else {
                        ALOGW("OMX service died without a death handler.");
                    }
                });
            }
        }

        {
            for (std::shared_ptr<Codec2Client> const& client :
                    Codec2Client::CreateFromAllServices()) {
                sp<IBase> base = client->getBase();
                deathNotifiers.emplace_back(
                        base, [l = wp<MediaPlayerBase>(p),
                               name = std::string(client->getServiceName())]() {
                    sp<MediaPlayerBase> listener = l.promote();
                    if (listener) {
                        ALOGI("Codec2 service \"%s\" died. "
                              "Sending death notification.",
                              name.c_str());
                        listener->sendEvent(
                                MEDIA_ERROR, MEDIA_ERROR_SERVER_DIED,
                                MEDIACODEC_PROCESS_DEATH);
                    } else {
                        ALOGW("Codec2 service \"%s\" died "
                              "without a death handler.",
                              name.c_str());
                    }
                });
            }
        }
    }

    Mutex::Autolock lock(mLock);

    mDeathNotifiers.clear();
    mDeathNotifiers.swap(deathNotifiers);
    mAudioDeviceUpdatedListener = new AudioDeviceUpdatedNotifier(p);

    if (!p->hardwareOutput()) {
        mAudioOutput = new AudioOutput(mAudioSessionId, IPCThreadState::self()->getCallingUid(),
                mPid, mAudioAttributes, mAudioDeviceUpdatedListener);
        static_cast<MediaPlayerInterface*>(p.get())->setAudioSink(mAudioOutput);
    }

    return p;
}
```

代码有点长，先看createPlayer

```cpp
sp<MediaPlayerBase> MediaPlayerService::Client::createPlayer(player_type playerType)
{

    sp<MediaPlayerBase> p = getPlayer();
    if ((p != NULL) && (p->playerType() != playerType)) {
        ALOGV("delete player");
        p.clear();
    }
    if (p == NULL) {

        p = MediaPlayerFactory::createPlayer(playerType, mListener, mPid);
    }

    if (p != NULL) {
        p->setUID(mUid);
    }

    return p;
}
```

又跑到MediaPlayerFactory::createPlayer里去createPlayer，刨根问底拦不住了，继续查，

```cpp
sp<MediaPlayerBase> MediaPlayerFactory::createPlayer(
        player_type playerType,
        const sp<MediaPlayerBase::Listener> &listener,
        pid_t pid) {
    sp<MediaPlayerBase> p;
    IFactory* factory;
    status_t init_result;
    Mutex::Autolock lock_(&sLock);

    if (sFactoryMap.indexOfKey(playerType) < 0) {
        ALOGE("Failed to create player object of type %d, no registered"
              " factory", playerType);
        return p;
    }

    factory = sFactoryMap.valueFor(playerType);
    CHECK(NULL != factory);

    p = factory->createPlayer(pid);

    if (p == NULL) {
        ALOGE("Failed to create player object of type %d, create failed",
               playerType);
        return p;
    }

    init_result = p->initCheck();
    if (init_result == NO_ERROR) {

        p->setNotifyCallback(listener);
    } else {
        ALOGE("Failed to create player object of type %d, initCheck failed"
              " (res = %d)", playerType, init_result);
        p.clear();
    }

    return p;
}
```

一个createPlayer层层剥离，终于看到希望在NuPlayerFactory中终于发现最终new 了一个NuPlayerDriver

```cpp
    virtual sp<MediaPlayerBase> createPlayer(pid_t pid) {
        ALOGV(" create NuPlayer");
        return new NuPlayerDriver(pid);
    }
};
```

整个createPlayer过程我们总结一下，从SetDataSource开始现根据跑分机制拿到playerType是NUPLAYER，根据playerType找到对应factory是NuplayerFactory然后create一个NuPlayerDriver。 回到setDataSource_pre继续，拿到NuPlayerDriver后，跳过中间无用的一些死亡代理，只剩一点逻辑

```cpp

    if (!p->hardwareOutput()) {
        mAudioOutput = new AudioOutput(mAudioSessionId, IPCThreadState::self()->getCallingUid(),
                mPid, mAudioAttributes, mAudioDeviceUpdatedListener);
        static_cast<MediaPlayerInterface*>(p.get())->setAudioSink(mAudioOutput);
    }
```

我们知道p即NuPlayerDriver，而hardwareOutput默认return false则便到了new AudioOutput中

```cpp
MediaPlayerService::AudioOutput::AudioOutput(audio_session_t sessionId, uid_t uid, int pid,
        const audio_attributes_t* attr, const sp<AudioSystem::AudioDeviceCallback>& deviceCallback)
    : mCallback(NULL),
      mCallbackCookie(NULL),
      mCallbackData(NULL),
      mStreamType(AUDIO_STREAM_MUSIC),
      mLeftVolume(1.0),
      mRightVolume(1.0),
      mPlaybackRate(AUDIO_PLAYBACK_RATE_DEFAULT),
      mSampleRateHz(0),
      mMsecsPerFrame(0),
      mFrameSize(0),
      mSessionId(sessionId),
      mUid(uid),
      mPid(pid),
      mSendLevel(0.0),
      mAuxEffectId(0),
      mFlags(AUDIO_OUTPUT_FLAG_NONE),
      mVolumeHandler(new media::VolumeHandler()),
      mSelectedDeviceId(AUDIO_PORT_HANDLE_NONE),
      mRoutedDeviceId(AUDIO_PORT_HANDLE_NONE),
      mDeviceCallbackEnabled(false),
      mDeviceCallback(deviceCallback)
{
    ALOGV("AudioOutput(%d)", sessionId);
    if (attr != NULL) {
        mAttributes = (audio_attributes_t *) calloc(1, sizeof(audio_attributes_t));
        if (mAttributes != NULL) {
            memcpy(mAttributes, attr, sizeof(audio_attributes_t));
            mStreamType = AudioSystem::attributesToStreamType(*attr);
        }
    } else {
        mAttributes = NULL;
    }

    setMinBufferCount();
}
```

new AudioOutput的过程初始化了好多东西，这里就不一一说了，等到具体用到时候在具体分析，这里简单提下mAttributes，这个是我们在java层setAudioAttributes传下来的，因此 **setAudioAttributes一定要在setDataSource前设置**， **这个是很多时候被忽略的错误**。拿到AudioOutput之后又调用了p.get())->setAudioSink(mAudioOutput)其实AudioOutput就是一个AudioSink，这个具体后续分析，还剩最后一块setDataSource_post这里主要的逻辑是 p->setDataSource(fd, offset, length)等分析到NuPlayerDriver的时候细说。

我们知道了MediaPlayerService是在mediaserver.rc中启动的，启动后通过工厂类的方式创建了NuplayerFactory和TestPlayerFactory，供我们播放使用，具体使用哪个player使根据我们setDataSource时会有个跑分机制选取的，之后我们又继续分析了SetDataSource的过程，通过java层的mediaplayer创建native层的MediaPlayer，然后在native层的setDataSource过程中，又会调用到MediaPlayerService中创建对应的client，client会最终创建NuPlayerDriver，总结一句话就是我们的setDataSource从Java到native又通过binder到service中的clent，最终到NuPlayerDriver里做codec。
（以上如有问题，欢迎大家交流指正~）
