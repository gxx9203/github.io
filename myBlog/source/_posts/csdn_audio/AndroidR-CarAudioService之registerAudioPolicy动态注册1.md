---
link: https://blog.csdn.net/l328873524/article/details/114857992
title: Android R- CarAudioService之registerAudioPolicy动态注册(一)
description: 前言我们解析完成car_audio_configuration.xml后，接下来就是动态路由策略的注册，以及多音区的焦点管理，本篇先看下动态路由策略。正文CarAudioService启动后，我们先回顾下setupDynamicRoutingLocked这个函数    private void setupDynamicRoutingLocked() {        final AudioPolicy.Builder builder = new AudioPolicy.Builder(mConte
keywords: Android R- CarAudioService之registerAudioPolicy动态注册(一)
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2021-03-16T17:57:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=35 sentences=66, words=363
---
## 前言

我们解析完成car_audio_configuration.xml后，接下来就是动态路由策略的注册，以及多音区的焦点管理，本篇先看下动态路由策略。

## 正文

CarAudioService启动后，我们先回顾下setupDynamicRoutingLocked这个函数

```java
    private void setupDynamicRoutingLocked() {
        final AudioPolicy.Builder builder = new AudioPolicy.Builder(mContext);
        builder.setLooper(Looper.getMainLooper());

        loadCarAudioZonesLocked();

        for (int i = 0; i < mCarAudioZones.size(); i++) {
            CarAudioZone zone = mCarAudioZones.valueAt(i);

            zone.synchronizeCurrentGainIndex();
            Log.v(CarLog.TAG_AUDIO, "Processed audio zone: " + zone);
        }

        CarAudioDynamicRouting.setupAudioDynamicRouting(builder, mCarAudioZones);

        builder.setAudioPolicyVolumeCallback(mAudioPolicyVolumeCallback);

        if (sUseCarAudioFocus) {

            mFocusHandler = new CarZonesAudioFocus(mAudioManager,
                    mContext.getPackageManager(),
                    mCarAudioZones,
                    mCarAudioSettings, ENABLE_DELAYED_AUDIO_FOCUS);
            builder.setAudioPolicyFocusListener(mFocusHandler);
            builder.setIsAudioFocusPolicy(true);
        }

        mAudioPolicy = builder.build();
        if (sUseCarAudioFocus) {

            mFocusHandler.setOwningPolicy(this, mAudioPolicy);
        }

        int r = mAudioManager.registerAudioPolicy(mAudioPolicy);
        if (r != AudioManager.SUCCESS) {
            throw new RuntimeException("registerAudioPolicy failed " + r);
        }

        setupOccupantZoneInfo();
    }
```

我们在[Android R- CarAudioService之car_audio_configuration.xml解析](https://blog.csdn.net/l328873524/article/details/113959900)中主要说了loadCarAudioZonesLocked过程，今天继续看下setupAudioDynamicRouting和registerAudioPolicy的过程，先看下时序图
![](https://img-blog.csdnimg.cn/20210316001724153.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70#pic_center)

好多for循环，一点点来看，先看下setupAudioDynamicRouting，两个参数，一个AudioPolicy的Builder，一个carAudioZones，逻辑不是很复杂，先遍历carAudioZones再遍历tVolumeGroups

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

我们在解析car_audio_configuration.xml的时候，知道有多个zone，每个zone有有多个group。每个group下有多个device，每个device下又有多个context，这个函数就是遍历每个group下的这些device和context内容。

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

这个函数就是动态路由的核心了，解析每个group下的device信息以及device下的context信息，context真正对应的是AudioAttributes的usage数组（一个context对应一个usage数组）,目前这个context除了关联AudioAttributes的usage之外，还有一点权限的check，在未发现，谷歌如此设计的寓意何为。这样就等于一个device对应多个usage数组。将一个device和多个usage数组组成一个audioMix 。也就是一个音频数据通路。当我们使用同一通路上这些AudioAttributes的usage进行播放时，声音都选择同一个AudioPolicy的策略上了。如下总结了Android AOSP代码中 bus与AudioAttributes的tree目录
![](https://img-blog.csdnimg.cn/20210317014031786.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70#pic_center)

![](https://img-blog.csdnimg.cn/2021031701404390.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70#pic_center)
![](https://img-blog.csdnimg.cn/20210317014056384.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70#pic_center)
下一篇分析registerAudioPolicy的过程。
