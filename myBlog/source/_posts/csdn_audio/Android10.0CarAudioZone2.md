---
link: https://blog.csdn.net/l328873524/article/details/105883712
title: Android10.0CarAudioZone（二）
description: 前言上一篇我们主要分析了关于CarAudioZone的CarVolumeGroup，今天我们继续看看剩下CarZonesAudioFocus正文首先还是看没有分析完setupDynamicRouting(SparseArray busToCarAudioDeviceInfo)的这个函数剩余部分        // Setup dynamic routing rules by usage ...
keywords: Android10.0CarAudioZone（二）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-05-02T16:36:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=32 sentences=24, words=348
---
上一篇我们主要分析了关于CarAudioZone的CarVolumeGroup，今天我们继续看看剩下CarZonesAudioFocus

首先还是看没有分析完setupDynamicRouting(SparseArray busToCarAudioDeviceInfo)的这个函数剩余部分

```java

        final CarAudioDynamicRouting dynamicRouting = new CarAudioDynamicRouting(mCarAudioZones);
        dynamicRouting.setupAudioDynamicRouting(builder);

        builder.setAudioPolicyVolumeCallback(mAudioPolicyVolumeCallback);

```

这部分后续说关于AUDIO_DEVICE_OUT_BUS的时候再说，主要做一个路由策略的处理。这里先不说了，继续看

```java
   if (sUseCarAudioFocus) {

            mFocusHandler = new CarZonesAudioFocus(mAudioManager,
                    mContext.getPackageManager(),
                    mCarAudioZones);
            builder.setAudioPolicyFocusListener(mFocusHandler);
            builder.setIsAudioFocusPolicy(true);
        }

        mAudioPolicy = builder.build();
        if (sUseCarAudioFocus) {

            mFocusHandler.setOwningPolicy(this, mAudioPolicy);
        }
```

sUseCarAudioFocus默认是true，如果我们不想在car上使用CarZonesAudioFocus这套逻辑，可以改变这个值为false，目前的版本未提供修改的方法，建议通过配置文件的方式修改，如果为false，则AudioFocus的处理就会使用原生的逻辑了。我们看下这段代码，首先new CarZonesAudioFocus

```java
    CarZonesAudioFocus(AudioManager audioManager,
            PackageManager packageManager,
            @NonNull CarAudioZone[] carAudioZones) {

        Preconditions.checkNotNull(carAudioZones);
        Preconditions.checkArgument(carAudioZones.length != 0,
                "There must be a minimum of one audio zone");

        for (CarAudioZone audioZone : carAudioZones) {
            Log.d(CarLog.TAG_AUDIO,
                    "CarZonesAudioFocus adding new zone " + audioZone.getId());
            CarAudioFocus zoneFocusListener = new CarAudioFocus(audioManager, packageManager);
            mFocusZones.put(audioZone.getId(), zoneFocusListener);
        }
    }
```

这里的逻辑主要是围绕carAudioZones处理的，上篇我们分析了carAudioZones是如何构建的，以及它的size是如何拿到的。其实这里根据carAudioZones为每个CarAudioZone创建一个 CarAudioFocus，那么我们也顺便看下CarAudioFocus

```java
    CarAudioFocus(AudioManager audioManager, PackageManager packageManager) {
        mAudioManager = audioManager;
        mPackageManager = packageManager;
    }
```

没啥逻辑，回到CarZonesAudioFocus中，最后将CarAudioFocus存入mFocusZones的map中。到此new CarZonesAudioFocus就结束了。我们继续看下setupDynamicRouting中的

```java
builder.setAudioPolicyFocusListener(mFocusHandler);
builder.setIsAudioFocusPolicy(true);
```

builder就是AudioPolicy的builder，在一进入setupDynamicRouting这个方法的时候就new了，这里将我们new的CarZonesAudioFocus作为参数通过setAudioPolicyFocusListener设置给了audiopolicy。那也就是说明了CarZonesAudioFocus应该是继承了setAudioPolicyFocusListener这里的参数，或者就是同一参数，我们再回到CarZonesAudioFocus的源码中看下

```java
class CarZonesAudioFocus extends AudioPolicy.AudioPolicyFocusListener
```

果然是继承了AudioPolicy.AudioPolicyFocusListener的，那我们在看下 AudioPolicy.AudioPolicyFocusListener里都有哪些方法，

```java
   public static abstract class AudioPolicyFocusListener {
        public void onAudioFocusGrant(AudioFocusInfo afi, int requestResult) {}
        public void onAudioFocusLoss(AudioFocusInfo afi, boolean wasNotified) {}

        public void onAudioFocusRequest(AudioFocusInfo afi, int requestResult) {}

        public void onAudioFocusAbandon(AudioFocusInfo afi) {}
    }
```

这里重写了两个onAudioFocusRequest和onAudioFocusAbandon，这俩主要处理音源焦点用的，这里先不细说。接下来builder.setIsAudioFocusPolicy(true);以及把audiopolicy传给 CarZonesAudioFocus即mFocusHandler.setOwningPolicy(this, mAudioPolicy)这样初始化就结束了， **我们简单总结一下CarZonesAudioFocus：首先在CarAudioService的初始化过程中会加载setupDynamicRouting,在setupDynamicRouting中会加载CarZonesAudioFocus，在CarZonesAudioFocus会根据传入的carAudioZones（上一篇分析过了主要管理音量，继xml解析有两个carAudioZone）创建对应个数的CarAudioFocus，目的就是把不同zone的音源分开处理。最后又将CarZonesAudioFocus注册给了AudioPolicy同时设置了setIsAudioFocusPolicy(true)（这个设置很重要，后面讲）** 到此基本就结束了。我们最后再看下CarAudioFocus，有个很重要的方法，先看一个二位数组

```java
    private static int sInteractionMatrix[][] = {

        {  0,       0,     0,   0,     0,    0,    0,     0,            0 },
        {  0,       1,     2,   1,     1,    1,    1,     2,            2 },
        {  0,       2,     2,   1,     2,    1,    2,     2,            2 },
        {  0,       2,     0,   2,     1,    1,    0,     0,            0 },
        {  0,       0,     2,   2,     2,    2,    0,     0,            2 },
        {  0,       0,     2,   0,     2,    2,    2,     2,            0 },
        {  0,       2,     2,   1,     1,    1,    2,     2,            2 },
        {  0,       2,     2,   1,     1,    1,    2,     2,            2 },
        {  0,       2,     2,   1,     1,    1,    2,     2,            2 },
    };
```

这个二维数组很有意思，一个行和列个数完全相同的矩阵。我们简单看下注释说明，行表示当前播放的context，列表述request的context，值表示3种意思 0、1、2分别代表

```java
    static final int INTERACTION_REJECT     = 0;
    static final int INTERACTION_EXCLUSIVE  = 1;
    static final int INTERACTION_CONCURRENT = 2;
```

这个注释连我这英语四级达不到的人来说都看懂了，我就不再翻译了。我举个简单例子，如果现在播放music，这个时候申请一个电话的音频焦点，是个什么结果呢，我们先找到music所在的行，是sInteractionMatrix[1][]在找下电话的列即sInteractionMatrix[1][3]，结果是1即Focus granted, others loose focus，也就是电话出声，音乐暂停，再找一个navi和music的是sInteractionMatrix[2][1]，对应的value是2，即navi和music混音。与我们日常使用场景一样。突然觉得这个东西好高大上，比起Android原生的也就是FocusRequester中的两个switch的判断优先级的结果高级了太多了。

通过这两篇文章，我觉得完成理解起来CarAudioZone还是有些困难的，我们后续会从一个具体的例子，以及具体的使用场景，来说明下个CarAudioZone是如何运行在Android的系统中的，以及又扮演着一个什么样的角色。
最后如果哪里说错啦，欢迎大家一起沟通交流~
