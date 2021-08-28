---
link: https://blog.csdn.net/l328873524/article/details/105924894
title: Android10.0CarAudioZone（三）
description: 前言我们前面两篇分析了CarAudioZone相关的声音以及音频焦点，基本控制流就差不多了，今天继续看下关于CarAudioZone相关的数据流。正文数据流这块与CarAudioZone的关系到不是很大，因为数据流底层没有zone的概念，只有bus的概念，那么什么是bus，是谷歌专为car弄得一套devices（这里的device概念是framework层的），即AUDIO_DEVICE_O...
keywords: Android10.0CarAudioZone（三）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-05-05T16:47:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=72 sentences=168, words=1267
---
我们前面两篇分析了CarAudioZone相关的声音以及音频焦点，基本控制流就差不多了，今天继续看下关于CarAudioZone相关的数据流。

数据流这块与CarAudioZone的关系是什么呢，数据流底层是一个bus的概念，那么什么是bus，是谷歌专为car弄得一套devices（这里的device概念是framework层的），即AUDIO_DEVICE_OUT_BUS。它和普通的device有什么区别呢，我们知道device的加载时通过audiopolicy来初始化的，在AudioPolicyService启动后会通过AudioPolicyManager来load audio_policy_configuration.xml，而在audio_policy_configuration.xml里定义了framework层所有的device。普通的device的type一定是不同的比如AUDIO_DEVICE_OUT_EARPIECE或者AUDIO_DEVICE_OUT_WIRED_HEADSET等，而使用bus的方式所有的device的type必须都是AUDIO_DEVICE_OUT_BUS，而且他们的address一定不为空，并且daddress的命名规则必须是busx_xxx或者bus00x_xxx，其中bus后面跟着的x必须是int，也就是这样bus1_xxx或者bus001_xxx.那么为什么这么命名呢，就进入了今天的正题。
CarAudioService的启动过程这里就不多说了，启动后加载了init，在init中通过AudioManager的getDevices(AudioManager.GET_DEVICES_OUTPUTS)获取了所有的用于输出的device，然后把这些device中type是BUS的过滤出来，所以说想使用bus的这套逻辑首先type必须是AUDIO_DEVICE_OUT_BUS。拿到这些type是AUDIO_DEVICE_OUT_BUS的device后重新构建了CarAudioDeviceInfo。然后便进入了setupDynamicRouting，从这个方法名称也可以看出设置动态路由，在setupDynamicRouting中我们之前的两篇分析了Volume和AudioFocus部分。但其中夹杂了两行代码

```java

        final CarAudioDynamicRouting dynamicRouting = new CarAudioDynamicRouting(mCarAudioZones);
        dynamicRouting.setupAudioDynamicRouting(builder);
```

我们进入CarAudioDynamicRouting看看

```java
    CarAudioDynamicRouting(CarAudioZone[] carAudioZones) {
        mCarAudioZones = carAudioZones;
    }
```

构造方法不说了，继续看下dynamicRouting.setupAudioDynamicRouting(builder)

```java
    void setupAudioDynamicRouting(AudioPolicy.Builder builder) {
        for (CarAudioZone zone : mCarAudioZones) {
            for (CarVolumeGroup group : zone.getVolumeGroups()) {
                setupAudioDynamicRoutingForGroup(group, builder);
            }
        }
    }
```

两个for循环，外层是mCarAudioZones即我们传入的mCarAudioZones的循环，我们继续看内层循环，我们还记得在分析[Android10.0CarAudioZone（一）](https://blog.csdn.net/l328873524/article/details/105803330)的时候说过CarVolumeGroup，每个CarAudioZone中包含多个CarVolumeGroup，这里拿出每一个CarVolumeGroup，和builder（audiopolicy的bulider）传递给setupAudioDynamicRoutingForGroup（个人吐槽下觉得这个写的还有优化的空间）

```java
    private void setupAudioDynamicRoutingForGroup(CarVolumeGroup group,
            AudioPolicy.Builder builder) {

        for (int busNumber : group.getBusNumbers()) {
            boolean hasContext = false;
            CarAudioDeviceInfo info = group.getCarAudioDeviceInfoForBus(busNumber);
            AudioFormat mixFormat = new AudioFormat.Builder()
                    .setSampleRate(info.getSampleRate())
                    .setEncoding(info.getEncodingFormat())
                    .setChannelMask(info.getChannelCount())
                    .build();
            AudioMixingRule.Builder mixingRuleBuilder = new AudioMixingRule.Builder();
            for (int contextNumber : group.getContextsForBus(busNumber)) {
                hasContext = true;
                int[] usages = getUsagesForContext(contextNumber);
                for (int usage : usages) {
                    mixingRuleBuilder.addRule(
                            new AudioAttributes.Builder().setUsage(usage).build(),
                            AudioMixingRule.RULE_MATCH_ATTRIBUTE_USAGE);
                }
                Log.d(CarLog.TAG_AUDIO, "Bus number: " + busNumber
                        + " contextNumber: " + contextNumber
                        + " sampleRate: " + info.getSampleRate()
                        + " channels: " + info.getChannelCount()
                        + " usages: " + Arrays.toString(usages));
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

又是各种for循环，我们一点一点分析，先看最外层的for，其中group.getBusNumbers()是什么呢？

```java
    int[] getBusNumbers() {
        final int[] busNumbers = new int[mBusToCarAudioDeviceInfo.size()];
        for (int i = 0; i < busNumbers.length; i++) {
            busNumbers[i] = mBusToCarAudioDeviceInfo.keyAt(i);
        }
        return busNumbers;
    }
```

mBusToCarAudioDeviceInfo就是我们在CarVolumeGroup的bind的时候构建的

```java
mContextToBus.put(contextNumber, busNumber);
mBusToCarAudioDeviceInfo.put(busNumber, info);
```

这里不说了，想看的可参照[Android10.0CarAudioZone（一）](https://blog.csdn.net/l328873524/article/details/105803330)，拿到busNumber后就可以得到CarAudioDeviceInfo，拿到info后又构建了一个AudioFormat。AudioFormat就不说了，接下来就是创建AudioMixingRule，然后便进入contextNumbers的一个循环，而contextNumbers是从mContextToBus根据bus取出的contextNUmbers

```java
    int[] getContextsForBus(int busNumber) {
        List<Integer> contextNumbers = new ArrayList<>();
        for (int i = 0; i < mContextToBus.size(); i++) {
            int value = mContextToBus.valueAt(i);
            if (value == busNumber) {
                contextNumbers.add(mContextToBus.keyAt(i));
            }
        }

        return contextNumbers.stream().mapToInt(i -> i).toArray();
    }
```

拿到了每个device下的contextNumbers数组后，在根据每个contextNumber取了一个usage的数组，即getUsagesForContext(contextNumber)

```java
    private int[] getUsagesForContext(int contextNumber) {
        final List<Integer> usages = new ArrayList<>();
        for (int i = 0; i < CarAudioDynamicRouting.USAGE_TO_CONTEXT.size(); i++) {
            if (CarAudioDynamicRouting.USAGE_TO_CONTEXT.valueAt(i) == contextNumber) {
                usages.add(CarAudioDynamicRouting.USAGE_TO_CONTEXT.keyAt(i));
            }
        }
        return usages.stream().mapToInt(i -> i).toArray();
    }
```

我们看下USAGE_TO_CONTEXT中usage和contextNumber的对应关系如下：

```java
    static {
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_UNKNOWN, ContextNumber.MUSIC);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_MEDIA, ContextNumber.MUSIC);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_VOICE_COMMUNICATION, ContextNumber.CALL);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING,
                ContextNumber.CALL);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_ALARM, ContextNumber.ALARM);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION, ContextNumber.NOTIFICATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION_RINGTONE, ContextNumber.CALL_RING);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST,
                ContextNumber.NOTIFICATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT,
                ContextNumber.NOTIFICATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_DELAYED,
                ContextNumber.NOTIFICATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_NOTIFICATION_EVENT, ContextNumber.NOTIFICATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY,
                ContextNumber.VOICE_COMMAND);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE,
                ContextNumber.NAVIGATION);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION,
                ContextNumber.SYSTEM_SOUND);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_GAME, ContextNumber.MUSIC);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_VIRTUAL_SOURCE, ContextNumber.INVALID);
        USAGE_TO_CONTEXT.put(AudioAttributes.USAGE_ASSISTANT, ContextNumber.VOICE_COMMAND);
    }
```

拿到usage后便 mixingRuleBuilder.addRule

```java
        public Builder addRule(AudioAttributes attrToMatch, int rule)
                throws IllegalArgumentException {
            if (!isValidAttributesSystemApiRule(rule)) {
                throw new IllegalArgumentException("Illegal rule value " + rule);
            }
            return checkAddRuleObjInternal(rule, attrToMatch);
        }
```

先看下这个isValidAttributesSystemApiRule，我们传入的是 AudioMixingRule.RULE_MATCH_ATTRIBUTE_USAGE

```java
    private static boolean isValidAttributesSystemApiRule(int rule) {

        switch (rule) {
            case RULE_MATCH_ATTRIBUTE_USAGE:
            case RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET:
                return true;
            default:
                return false;
        }
    }
```

，即return checkAddRuleObjInternal。我们继续看下checkAddRuleObjInternal

```java
        private Builder checkAddRuleObjInternal(int rule, Object property)
                throws IllegalArgumentException {
            if (property == null) {
                throw new IllegalArgumentException("Illegal null argument for mixing rule");
            }
            if (!isValidRule(rule)) {
                throw new IllegalArgumentException("Illegal rule value " + rule);
            }
            final int match_rule = rule & ~RULE_EXCLUSION_MASK;
            if (isAudioAttributeRule(match_rule)) {
                if (!(property instanceof AudioAttributes)) {
                    throw new IllegalArgumentException("Invalid AudioAttributes argument");
                }
                return addRuleInternal((AudioAttributes) property, null, rule);
            } else {

                if (!(property instanceof Integer)) {
                    throw new IllegalArgumentException("Invalid Integer argument");
                }
                return addRuleInternal(null, (Integer) property, rule);
            }
        }
```

又是一个isValidRule的判断，这里返回时true，

```java
    private static boolean isValidRule(int rule) {
        final int match_rule = rule & ~RULE_EXCLUSION_MASK;
        switch (match_rule) {
            case RULE_MATCH_ATTRIBUTE_USAGE:
            case RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET:
            case RULE_MATCH_UID:
                return true;
            default:
                return false;
        }
    }
```

继续又做了一个isAudioAttributeRule判断

```java
    private static boolean isAudioAttributeRule(int match_rule) {
        switch(match_rule) {
            case RULE_MATCH_ATTRIBUTE_USAGE:
            case RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET:
                return true;
            default:
                return false;
        }
    }
```

还是return true，进入 addRuleInternal((AudioAttributes) property, null, rule);这个方法

```java
        private Builder addRuleInternal(AudioAttributes attrToMatch, Integer intProp, int rule)
                throws IllegalArgumentException {

            if (mTargetMixType == AudioMix.MIX_TYPE_INVALID) {

                if (isPlayerRule(rule)) {
                    mTargetMixType = AudioMix.MIX_TYPE_PLAYERS;
                } else {
                    mTargetMixType = AudioMix.MIX_TYPE_RECORDERS;
                }
            } else if (((mTargetMixType == AudioMix.MIX_TYPE_PLAYERS) && !isPlayerRule(rule))
                    || ((mTargetMixType == AudioMix.MIX_TYPE_RECORDERS) && isPlayerRule(rule)))
            {
                throw new IllegalArgumentException("Incompatible rule for mix");
            }
            synchronized (mCriteria) {
                Iterator<AudioMixMatchCriterion> crIterator = mCriteria.iterator();
                final int match_rule = rule & ~RULE_EXCLUSION_MASK;

                while (crIterator.hasNext()) {
                    final AudioMixMatchCriterion criterion = crIterator.next();

                    if ((criterion.mRule & ~RULE_EXCLUSION_MASK) != match_rule) {
                        continue;
                    }
                    switch (match_rule) {
                        case RULE_MATCH_ATTRIBUTE_USAGE:

                            if (criterion.mAttr.getUsage() == attrToMatch.getUsage()) {
                                if (criterion.mRule == rule) {

                                    return this;
                                } else {

                                    throw new IllegalArgumentException("Contradictory rule exists"
                                            + " for " + attrToMatch);
                                }
                            }
                            break;
                        case RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET:

                            if (criterion.mAttr.getCapturePreset() == attrToMatch.getCapturePreset()) {
                                if (criterion.mRule == rule) {

                                    return this;
                                } else {

                                    throw new IllegalArgumentException("Contradictory rule exists"
                                            + " for " + attrToMatch);
                                }
                            }
                            break;
                        case RULE_MATCH_UID:

                            if (criterion.mIntProp == intProp.intValue()) {
                                if (criterion.mRule == rule) {

                                    return this;
                                } else {

                                    throw new IllegalArgumentException("Contradictory rule exists"
                                            + " for UID " + intProp);
                                }
                            }
                            break;
                    }
                }

                switch (match_rule) {
                    case RULE_MATCH_ATTRIBUTE_USAGE:
                    case RULE_MATCH_ATTRIBUTE_CAPTURE_PRESET:

                        mCriteria.add(new AudioMixMatchCriterion(attrToMatch, rule));
                        break;
                    case RULE_MATCH_UID:
                        mCriteria.add(new AudioMixMatchCriterion(intProp, rule));
                        break;
                    default:
                        throw new IllegalStateException("Unreachable code in addRuleInternal()");
                }
            }
            return this;
        }
```

到此 addRule的过程就结束了，我们简单总结一下**， **首先通过传入的mCarAudioZones遍历其中的每个CarAudioZone，每个CarAudioZone又包含一个CarVolumeGroup集合，遍历CarVolumeGroup里的每个group，每个group又包含一个devices的集合（CarAudioDeviceInfo的map，这个map的key是busNumber），每个device又包含一个context的集合（contextNumber和busNumber组成的map），说的有点乱，但我们一定要把这些关系捋清楚。这样层层循环后我们拿到了contextNumber后通过map拿到usage数组，归根揭底就是把Audio Attribute的usage数组和context以及CarAudioDeviceInfo都关联上****。最终的关联我们又回到CarAudioDynamicRouting的 setupAudioDynamicRoutingForGroup中

```java
    if (hasContext) {

                AudioMix audioMix = new AudioMix.Builder(mixingRuleBuilder.build())
                        .setFormat(mixFormat)
                        .setDevice(info.getAudioDeviceInfo())
                        .setRouteFlags(AudioMix.ROUTE_FLAG_RENDER)
                        .build();
                builder.addMix(audioMix);
            }
```

AudioMix 包含了有usage数组的mixingRuleBuilder和AudioDeviceInfo， **这样device与usage数组便对应到了一起，我们知道原生的Android是通过stream在AudioPolicyManager的Engine中选择的device，而在Car的这套逻辑中通过usage和device在上层（java）就配置好了**。这里的builder就是audioPolicy，addMix是简单的将audioMix传递到了audiopolicy中

```java
        public Builder addMix(@NonNull AudioMix mix) throws IllegalArgumentException {
            if (mix == null) {
                throw new IllegalArgumentException("Illegal null AudioMix argument");
            }
            mMixes.add(mix);
            return this;
        }
```

mMixes即

```java
ArrayList<AudioMix> mMixes
```

我们继续看下，就又回到了CarAudioService的setupDynamicRouting中

```java
mAudioPolicy = builder.build();
```

开始了audiopolicy的bulid

```java
        public AudioPolicy build() {
            if (mStatusListener != null) {

                for (AudioMix mix : mMixes) {
                    mix.mCallbackFlags |= AudioMix.CALLBACK_FLAG_NOTIFY_ACTIVITY;
                }
            }
            if (mIsFocusPolicy && mFocusListener == null) {
                throw new IllegalStateException("Cannot be a focus policy without "
                        + "an AudioPolicyFocusListener");
            }
            return new AudioPolicy(new AudioPolicyConfig(mMixes), mContext, mLooper,
                    mFocusListener, mStatusListener, mIsFocusPolicy, mIsTestFocusPolicy,
                    mVolCb, mProjection);
        }
    }
```

创建了一个AudioPolicyConfig然后用来构建AudioPolicy，这里也是简单看下AudioPolicyConfig的构造函数吧

```java
    AudioPolicyConfig(ArrayList<AudioMix> mixes) {
        mMixes = mixes;
    }
```

简单过了，再看下AudioPolicy的构造函数

```java
    private AudioPolicy(AudioPolicyConfig config, Context context, Looper looper,
            AudioPolicyFocusListener fl, AudioPolicyStatusListener sl,
            boolean isFocusPolicy, boolean isTestFocusPolicy,
            AudioPolicyVolumeCallback vc, @Nullable MediaProjection projection) {
        mConfig = config;
        mStatus = POLICY_STATUS_UNREGISTERED;
        mContext = context;
        if (looper == null) {
            looper = Looper.getMainLooper();
        }
        if (looper != null) {
            mEventHandler = new EventHandler(this, looper);
        } else {
            mEventHandler = null;
            Log.e(TAG, "No event handler due to looper without a thread");
        }
        mFocusListener = fl;
        mStatusListener = sl;
        mIsFocusPolicy = isFocusPolicy;
        mIsTestFocusPolicy = isTestFocusPolicy;
        mVolCb = vc;
        mProjection = projection;
    }
```

也是一些赋值，具体看下，**其中mConfig是我们刚才new的，mFocusListener 是mFocusHandler即我们之前new的 CarZonesAudioFocus，mStatusListener这里为null，mIsFocusPolicy我们之前设置为了true，mIsTestFocusPolicy是false，mVolCb 即mAudioPolicyVolumeCallback，mProjection这里也为null。**到这里我们AudioPolicy也build结束了。剩下来的就是

```java
mAudioManager.registerAudioPolicy(mAudioPolicy);
```

将AudioPolicy注册下去了，我们下篇在讲

在CarAudioService的初始化过程中，通过car_audio_configuration.xml做了volume 、audiofocus以及device的多分区的配置， **如何让我们的应用对应到不同的分区上，主要是通过uid处理的（这块逻辑后面说）**。 **今天我们主要分析的是devic的动态路由，通过遍历mCarAudioZones中的每个CarAudioZone，然后再遍历每个CarAudioZone中的CarVolumeGroup集合，遍历CarVolumeGroup里的每个group，再遍历每个group中的devices的集合（CarAudioDeviceInfo的map，这个map的key是busNumber），最后遍历device中的一个context的集合（contextNumber和busNumber组成的map），把所有conrextNumber对应的usage全部拿出来放到usage数组中。最后把这个usage数组以及他对应的外层的deviceInfo一起存入AudioMix中，再被add到AudioPolicy中，这块归根揭底就是把Audio Attribute的usage数组和CarAudioDeviceInfo关联上。这样我们最终通过mAudioManager.registerAudioPolicy(mAudioPolicy)注册下去**。
如有问题，欢迎大家随时沟通~
