---
link: https://blog.csdn.net/l328873524/article/details/114993540
title: Android R- CarAudioService之registerAudioPolicy动态注册(二)
description: 前言Android 在O之后增加了CarAudio，增加了多音区，增加了动态路由，而对于Audio的三大块AudioTrack、AudioFlinger和AudioPolicy。CarAudio主要解决的就是车载上的AudioPolicy策略。我们之前分析了car_audio_configuration.xml的解析，以及解析后如何构建路由策略和多音区的AudioFocus，今天继续分析。解析后的路由策略是如何注册到AudioPlolicy中，以及如何应用在我们系统中的。正文在整个CarAudio启动
keywords: Android R- CarAudioService之registerAudioPolicy动态注册(二)
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2021-05-13T16:00:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=17 sentences=71, words=299
---
## 前言

Android 在O之后增加了CarAudio，增加了多音区，增加了动态路由，而对于Audio的三大块AudioTrack、AudioFlinger和AudioPolicy。CarAudio主要解决了车载上的AudioPolicy策略。我们之前分析了car_audio_configuration.xml的解析，以及解析后如何构建路由策略和多音区的AudioFocus，今天继续分析。解析后的路由策略是如何注册到AudioPlolicy中，以及如何应用在我们系统中的。

## 正文

在整个CarAudio启动时，核心初始化的就是setupDynamicRouting()函数，我们七七八八也分析的差不多了，最后分析下解析完的xml，做好的路由策略是如何注册下去的，还是先看下时序图，首先是构建AudioPolcy的时序：
![](https://img-blog.csdnimg.cn/20210513223235546.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70)
我们直接进CarAudioDynamicRouting里看下：

```java
    static void setupAudioDynamicRouting(AudioPolicy.Builder builder,
            SparseArray<CarAudioZone> carAudioZones) {
        for (int i = 0; i < carAudioZones.size(); i++) {
            CarAudioZone zone = carAudioZones.valueAt(i);
            for (CarVolumeGroup group : zone.getVolumeGroups()) {
                setupAudioDynamicRoutingForGroup(group, builder);
            }
        }
    }
```

这个函数没啥说的，比较简单，我们举例来说明下吧，在[Android R- CarAudioService之registerAudioPolicy动态注册(一)](https://blog.csdn.net/l328873524/article/details/114857992?spm=1001.2014.3001.5502)中，我们知道有carAudioZones有3个，这里以primary zone举例，他有四个group。继续看下setupAudioDynamicRoutingForGroup

```java
    private static void setupAudioDynamicRoutingForGroup(CarVolumeGroup group,
            AudioPolicy.Builder builder) {

        for (String address : group.getAddresses()) {
            boolean hasContext = false;
            CarAudioDeviceInfo info = group.getCarAudioDeviceInfoForAddress(address);
            AudioFormat mixFormat = new AudioFormat.Builder()
                    .setSampleRate(info.getSampleRate())
                    .setEncoding(info.getEncodingFormat())
                    .setChannelMask(info.getChannelCount())
                    .build();
            AudioMixingRule.Builder mixingRuleBuilder = new AudioMixingRule.Builder();
            for (int carAudioContext : group.getContextsForAddress(address)) {
                hasContext = true;
                int[] usages = CarAudioContext.getUsagesForContext(carAudioContext);
                for (int usage : usages) {
                    AudioAttributes attributes = buildAttributesWithUsage(usage);
                    mixingRuleBuilder.addRule(attributes,
                            AudioMixingRule.RULE_MATCH_ATTRIBUTE_USAGE);
                }
                if (Log.isLoggable(CarLog.TAG_AUDIO, Log.DEBUG)) {
                    Log.d(CarLog.TAG_AUDIO, String.format(
                            "Address: %s AudioContext: %s sampleRate: %d channels: %d usages: %s",
                            address, carAudioContext, info.getSampleRate(), info.getChannelCount(),
                            Arrays.toString(usages)));
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
    }
```

代码比较长，但很重要，先看第一个for循环即 (String address : group.getAddresses()) ，我们知道每个group都会至少有一个bus，每个bus都会有一个addrss。比如还是在[Android R- CarAudioService之registerAudioPolicy动态注册(一)](https://blog.csdn.net/l328873524/article/details/114857992?spm=1001.2014.3001.5502)中我们的primary zone中group0中有bus0、bus3、bus6和bus7，group1中有bus1和bus2，group2中有bus4，group3中有bus5.这里取出每个bus中一些配置信息，这些bus的信息是来自audio_policy_configuration.xml中的，截取一段bus0的如下：

```xml
            <devicePorts>
                <devicePort tagName="bus0_media_out" role="sink" type="AUDIO_DEVICE_OUT_BUS"
                        address="bus0_media_out">
                    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
                            samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
                    <gains>
                        <gain name="" mode="AUDIO_GAIN_MODE_JOINT"
                                minValueMB="-3200" maxValueMB="600" defaultValueMB="0" stepValueMB="100"/>
                    gains>
                devicePort>
```

然后构建AudioFormat的SampleRate、Encoding、ChannelMask，如上图就是48000、AUDIO_FORMAT_PCM_16_BIT、和AUDIO_CHANNEL_OUT_STEREO。
接下来又是一个for循环，因为每个bus下都至少有一个carAudioContext ，例如primary zone中的bus0下有个carAudioContext Music，而rear seat zone1和 rear seat zone2中每个bus下都是很多context的。这里的第二个for循环就是遍历每个bus下的carAudioContext ，为什么要遍历carAudioContext呢？其实最主要的就是找AudioAttributes的Usage，我们在Android8.0之前的版本AudioPolicyManager的路由策略都是根据播放AudioTrack或者MediaPlayer的StreamType来处理的。但是CarAudio的动态路由是根据Usage来处理的。还是看下在[Android R- CarAudioService之registerAudioPolicy动态注册(一)](https://blog.csdn.net/l328873524/article/details/114857992?spm=1001.2014.3001.5502)中，每个carAudioContext下都有至少1个usage，这里就是要找出所有的usage。然后加到AudioMixingRule中，addRule的过程就不说了，他们最终都被放到AudioMixMatchCriterion集合中了，AudioMixMatchCriterion有3个属性其中Rule是 **RULE_MATCH_ATTRIBUTE_USAGE**，IntProp是 Integer.MIN_VALUE，以及传入的AudioAttributes，还有他们的mTargetMixType 是AudioMix. **MIX_TYPE_PLAYERS**。
最后把这个 AudioMixingRule添加到AudioMix中，具体代码也不细说了，再记住一个属性mRouteFlags是AudioMix. **ROUTE_FLAG_RENDER** 。这些后面会用到。

## 总结

到这里我们来总结下，解析完成XMl后便进入到 CarAudioDynamicRouting中来构建动态路由策略，大体步骤如下：
1.循环处理Zones下的每个zone
1.1循环处理zone下的每个volumegroup
1.1.1循环处理volumegroup下的每个bus，同时每个bus对应创建了一个AudioMixingRule
1.1.1.1循环处理bus下的每个caraudiocontext
1.1.1.1.1循环处理caraudiocontext下的每个usage
1.1.1.1.1.1将bus下的每个caraudiocontext以及每个caraudiocontext下usage全部加入到AudioMixingRule中，感觉有点绕，其实我也没有get到谷歌搞caraudiocontext的用意,感觉很啰嗦，这个简单说就是把bus下所有的usage全部加到AudioMixingRule中。
1.1.1.2将每个bus的device信息加上AudioMixingRule 然后创建一个AudioMix，这个AudioMix化繁入简，说白了就是一个device对应了一群usage，多少有点路由的概念了。
1.1.1.3最后将AudioMix加到AudioPolicy中。

由于谷歌把CarAudioVolume、CarAudioZone、以及CarAudioFocus都融合到一起了，所以这块看起来有点乱，尤其一个接一个的for循环。
归根结底就是将bus和usage对应上（1个bus对应一群usage），不同的bus可以有相同的usage，但前提相同usage对应的bus一定是不同zone的。这个后面说同一个应用如何播放到不同音区上时再说。

所以我们在做定制路由策略的时候，一定要考虑好，哪些Usage放到同一个bus上。哪些bus放到同一个group中。

下一篇继续说如何将添加到AudioPolicy中的路由策略注册到FW的AudioPolicyManager中的。
