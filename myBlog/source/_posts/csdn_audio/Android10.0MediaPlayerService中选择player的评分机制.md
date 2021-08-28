---
link: https://blog.csdn.net/l328873524/article/details/105622194
title: Android10.0MediaPlayerService中选择player的评分机制
description: 前言
keywords: Android10.0MediaPlayerService中选择player的评分机制
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-20T16:33:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=60 sentences=43, words=660
---
我们知道MediaPlayer播放的时候，最终会调到native层的MediaPlayerService中，在MediaPlayerService中会创建NuPlayer和TestPlayer，那么这俩Player是如何选择的呢？就涉及到了选择player的得分机制。

先看下MediaPlayerService创建player的过程，首先MediaPlayerService在启动的时候

```cpp
MediaPlayerService::MediaPlayerService()
{
    ALOGV("MediaPlayerService created");
    mNextConnId = 1;

    MediaPlayerFactory::registerBuiltinFactories();
}
```

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

分别new了两个factory，NuPlayerFactory和TestPlayerFactory，并分别调用了registerFactory_l，那么继续看下registerFactory_l

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

将NuPlayerFactory和TestPlayerFacory加入到容器sFactoryMap中。到此MediaPlayerService就初始化完成了。简单总结一下就是MediaPlayerService初始化的时候通过MediaPlayerFactory分别创建了NuPlayerFactory和TestPlayerFacory，并将两个factory加入到容器sFactoryMap中。
那么我们是在什么时候选取的player呢，其实是在我们SetDataSource的时候，我们知道MediaPlayer的java层Api暴露的SetDataSource的接口很多，我粗略看了下不管是hide还是systemapi的一共11个，其实这么多对应到native层就三个分别是

```cpp
status_t MediaPlayer::setDataSource(
        const sp<IMediaHTTPService> &httpService,
        const char *url, const KeyedVector<String8, String8> *headers)
```

```cpp
status_t MediaPlayer::setDataSource(int fd, int64_t offset, int64_t length)

```

```cpp
status_t MediaPlayer::setDataSource(const sp<IDataSource> &source)
```

我们使用最多的是第一种和第二种，分别播放的是uri和path，在native的mediaplayer中setDataSource会调用的MediaPlayerService的

```cpp
status_t MediaPlayerService::Client::setDataSource(
        const sp<IDataSource> &source) {
    sp<DataSource> dataSource = CreateDataSourceFromIDataSource(source);
    player_type playerType = MediaPlayerFactory::getPlayerType(this, dataSource);
    sp<MediaPlayerBase> p = setDataSource_pre(playerType);
    if (p == NULL) {
        return NO_INIT;
    }

    return mStatus = setDataSource_post(p, p->setDataSource(dataSource));
}
```

这里简单列出了一个Media Player Service中的setDataSource的源码，其实不管哪个最终调用的都是MediaPlayerFactory的getPlayerType

```cpp
player_type MediaPlayerFactory::getPlayerType(const sp<IMediaPlayer>& client,
                                              const char* url) {
    GET_PLAYER_TYPE_IMPL(client, url);
}

player_type MediaPlayerFactory::getPlayerType(const sp<IMediaPlayer>& client,
                                              int fd,
                                              int64_t offset,
                                              int64_t length) {
    GET_PLAYER_TYPE_IMPL(client, fd, offset, length);
}

player_type MediaPlayerFactory::getPlayerType(const sp<IMediaPlayer>& client,
                                              const sp<IStreamSource> &source) {
    GET_PLAYER_TYPE_IMPL(client, source);
}

player_type MediaPlayerFactory::getPlayerType(const sp<IMediaPlayer>& client,
                                              const sp<DataSource> &source) {
    GET_PLAYER_TYPE_IMPL(client, source);
}
```

选取PlayerType的时候代码如下

```cpp
#define GET_PLAYER_TYPE_IMPL(a...)                      \
    Mutex::Autolock lock_(&sLock);                      \
                                                        \
    player_type ret = STAGEFRIGHT_PLAYER;               \
    float bestScore = 0.0;                              \
                                                        \
    for (size_t i = 0; i < sFactoryMap.size(); ++i) {   \
                                                        \
        IFactory* v = sFactoryMap.valueAt(i);           \
        float thisScore;                                \
        CHECK(v != NULL);                               \
        thisScore = v->scoreFactory(a, bestScore);      \
        if (thisScore > bestScore) {                    \
            ret = sFactoryMap.keyAt(i);                 \
            bestScore = thisScore;                      \
        }                                               \
    }                                                   \
                                                        \
    if (0.0 == bestScore) {                             \
        ret = getDefaultPlayerType();                   \
    }                                                   \
                                                        \
    return ret;
```

我们先看下playerType的定义

```cpp

enum player_type {
    STAGEFRIGHT_PLAYER = 3,
    NU_PLAYER = 4,

    TEST_PLAYER = 5,
};

```

只有3个，1和2可能是早期的版本使用的，后来被移除了。STAGEFRIGHT_PLAYER这里基本也不用了，虽然这里playerType默认STAGEFRIGHT_PLAYER，但真正选择默认player的时候，是NU_PLAYER。我们继续看这个函数bestScore 是最终得分，thisScore是当前的分数，我们分析MediaPlayer初始化的时候知道了sFactoryMap其实只存储了两个值，分别是NU_PLAYER和TEST_PLAYER。那么我们就分别看下这俩fatory的scoreFactory

```cpp
class NuPlayerFactory : public MediaPlayerFactory::IFactory {
  public:
    virtual float scoreFactory(const sp<IMediaPlayer>& ,
                               const char* url,
                               float curScore) {
        static const float kOurScore = 0.8;

        if (kOurScore  curScore)
            return 0.0;

        if (!strncasecmp("http://", url, 7)
                || !strncasecmp("https://", url, 8)
                || !strncasecmp("file://", url, 7)) {
            size_t len = strlen(url);
            if (len >= 5 && !strcasecmp(".m3u8", &url[len - 5])) {
                return kOurScore;
            }

            if (strstr(url,"m3u8")) {
                return kOurScore;
            }

            if ((len >= 4 && !strcasecmp(".sdp", &url[len - 4])) || strstr(url, ".sdp?")) {
                return kOurScore;
            }
        }

        if (!strncasecmp("rtsp://", url, 7)) {
            return kOurScore;
        }

        return 0.0;
    }

    virtual float scoreFactory(const sp<IMediaPlayer>& ,
                               const sp<IStreamSource>& ,
                               float ) {
        return 1.0;
    }

    virtual float scoreFactory(const sp<IMediaPlayer>& ,
                               const sp<DataSource>& ,
                               float ) {

        return 1.0;
    }
```

对于url的的得分计算还算不错，大概根据url来处理，是0.8分还是0.0分的。对于剩下两种情况就比较敷衍了，直接得分1.0.我们在看下TestPlayerFactory 的得分机制

```cpp
class TestPlayerFactory : public MediaPlayerFactory::IFactory {
  public:
    virtual float scoreFactory(const sp<IMediaPlayer>& ,
                               const char* url,
                               float ) {
        if (TestPlayerStub::canBeUsed(url)) {
            return 1.0;
        }

        return 0.0;
    }
```

如果canBeUsed则得1.0分否则得0.0分，我们看下canBeUsed这个函数

```cpp
 bool TestPlayerStub::canBeUsed(const char *url)
{
    return isTestBuild() && isTestUrl(url);
}
```

其中isTestBuild

```cpp

bool isTestBuild()
{
    char prop[PROPERTY_VALUE_MAX] = { '\0', };

    property_get(kBuildTypePropName, prop, "\0");
    return strcmp(prop, kEngBuild) == 0 || strcmp(prop, kTestBuild) == 0;
}
```

注释说的已经很清楚了，我们build的是一个eng或者test的版本，并且isTestUrl的时候我们就使用TestPlayer，那么什么样的url是testUrl呢

```cpp

bool isTestUrl(const char *url)
{
    return url && strncmp(url, kTestUrlScheme, strlen(kTestUrlScheme)) == 0;
}
```

原来是以'test:'这种开头的url。到此我们大概就明白了什么时候选取什么样的player了。
回到最初得分的那个函数里，如果我们thisScore > bestScore，那么最终得分bestScore = thisScore ，如果一顿操作猛如虎后，bestScore仍是0.0，那么就要使用getDefaultPlayerType()了。

```cpp
static player_type getDefaultPlayerType() {
    return NU_PLAYER;
}
```

感觉像是被耍了一样，直接return NU_PLAYER不好吗？为何还要在开头搞个player_type ret = STAGEFRIGHT_PLAYER，来吓唬人。
到此拿到player_type后，后面的就是创建对应的player了。这里就不在分析了。

对于Android的早期版本关注不是很多，或许早期版本的player有多个以及复杂的得分机制。但是最近几个版本，包括我们此次分析的Android10.0.对于mediaPlayer的选取以及得分的机制都简单了很多，或许谷歌只是想提供基本的播放和测试，剩下的就让大家随便定制的。
总结下来，我们player的得分机制是在setDataSource的时候，通过MediaPlayerFactory选取对应的player_type 。最终创建需要的player。
（以上，如有问题，欢迎大家执政交流）
