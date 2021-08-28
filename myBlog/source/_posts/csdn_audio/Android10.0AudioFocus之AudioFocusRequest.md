---
link: https://blog.csdn.net/l328873524/article/details/105256881
title: Android10.0AudioFocus之AudioFocusRequest
description: AudioFocus相关类的说明
keywords: Android10.0AudioFocus之AudioFocusRequest
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-01T16:02:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=30 sentences=12, words=271
---
以前做Android4.0的时候申请AudioFocus基本就是传个streamtype，durationHint和listener，不知不觉到了android O、P、Q。也就是到了Android10.0发现突然多了好多与音频焦点相关的类，看的眼花缭乱。今天抽时间梳理了一下这些类都是做什么的。

具体罗列如下：

* AudioFocusRequest
* FocusRequestInfo
* AudioFocusInfo
* FocusRequester
是不是第一次看也是一脸懵逼，那么我们就从源码角度来逐一分析。
首先几天先看下AudioFocusRequest，这个是我们在申请音频焦点和释放音频焦点需要传入的参数，主要是设置申请焦点时的一些参数设定。

我摘录了源码注释部分，这块主要分了四部分：

个人英语水平有限，就不卖弄了，原文大家自行翻译吧。

这个类采用的也是这种builder的设计模式，这种模式的优点就是我们可以只初始化我们关心的参数那么接下来我们继续分析都做了什么

```java
       public @NonNull Builder setFocusGain(int focusGain) {
            if (!isValidFocusGain(focusGain)) {
                throw new IllegalArgumentException("Illegal audio focus gain type " + focusGain);
            }
            mFocusGain = focusGain;
            return this;
        }
```

先说一个这个，这个是我一直觉得很尴尬的一个方法，因为我们在使用build的方式创建AudioFocusRequest的时候我们要传入一个focusGain

```java
        public Builder(int focusGain) {
            setFocusGain(focusGain);
        }
```

那么这个方法就显得有些多余了，直到某一天我才蓦然发现其实我们也可以不通过build的方式创建AudioFocusRequest，那么这个方法就显得尤为重要了。这个方法我们采用build的方式构建AudioFocusRequest的时候就不用再次设置了，否则一定需要设置的。因为默认的focusGain是0，而我们在requestAudioFocus的时候会对focusGain进行check检查

```java
  if (!AudioFocusRequest.isValidFocusGain(durationHint)) {
            throw new IllegalArgumentException("Invalid duration hint");
        }

```

满足需求的focusGain如下

```java
    final static boolean isValidFocusGain(int focusGain) {
        switch (focusGain) {
            case AudioManager.AUDIOFOCUS_GAIN:
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT:
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK:
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE:
                return true;
            default:
                return false;
        }
    }
```

没有 AudioManager.AUDIOFOCUS_NONE，因此我们一定要setFocusGain。
继续

```java
        public @NonNull Builder setOnAudioFocusChangeListener(
                @NonNull OnAudioFocusChangeListener listener) {
            if (listener == null) {
                throw new NullPointerException("Illegal null focus listener");
            }
            mFocusListener = listener;
            mListenerHandler = null;
            return this;
        }

        @NonNull Builder setOnAudioFocusChangeListenerInt(
                OnAudioFocusChangeListener listener, Handler handler) {
            mFocusListener = listener;
            mListenerHandler = handler;
            return this;
        }

        public @NonNull Builder setOnAudioFocusChangeListener(
                @NonNull OnAudioFocusChangeListener listener, @NonNull Handler handler) {
            if (listener == null || handler == null) {
                throw new NullPointerException("Illegal null focus listener or handler");
            }
            mFocusListener = listener;
            mListenerHandler = handler;
            return this;
        }

```

三个setListener的方法，关于第二个我一直没有看明白，因为没有参数校验，我只能怀疑是为了兼容以前版本，而以前版本这个listener可以为null，或者现在的版本某些情况不需要这个listener所以允许传null。但我又未发现使用的地方。这个不说了，来说下一和三的区别，也就是有没有handler。区别在于有handler我们可以指定lisnter回调到handler线程，而没有handler只能默认回调到与我们初始化audiomanager的那个线程，因此建议还是单独回调到指定的handler线程，因为如果使用audiomanager也就是申请焦点的线程容易造成listener回调的卡顿，这样造成的后果就是我们要停止的声音没有及时停止而造成了短暂混音。

这个我当时做android4.0的时候确实遇到过，当时是播放音乐和申请焦点是一个线程，因为那个时候还有没AudioFocusRequest，所以当时解决的方式就是把申请焦点的逻辑单独拿到一个线程去处理的，不过现在简单多了，我们传个handler就可以了，显然谷歌也是发现了这个可能出现的问题。
有点跑题了继续分析

```java
        public @NonNull Builder setAudioAttributes(@NonNull AudioAttributes attributes) {
            if (attributes == null) {
                throw new NullPointerException("Illegal null AudioAttributes");
            }
            mAttr = attributes;
            return this;
        }
```

这个不多说了，设置audioAttributes，这里虽然对AudioAttributes的usage和contentType没有啥要求，但建议设置为与我们申请焦点目的相关的属性，比如我们申请焦点是为了播放音乐，那么我们的AudioAttributes的usage和contentType就可以设置成music，这样我们在使用Mediaplayer或者AudioTrack播放的时候可以直接设置这个AudioAttributes，就不用在重新弄一个了。

```java
        public @NonNull Builder setWillPauseWhenDucked(boolean pauseOnDuck) {
            mPausesOnDuck = pauseOnDuck;
            return this;
        }
```

这个方法是说当前音源在收到AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK这个callback的时候，是否自动duck（降低声音）处理。如果我们设置了true，那么就不会执行duck，举个例子比如我们在放音乐，当导航播报的时候会发现音乐的声音变低了（尤其车载系统中），导航播放结束音乐的声音又回到了之前的音量这种效果就是设置了setWillPauseWhenDucked（false）。

```java
        public @NonNull Builder setAcceptsDelayedFocusGain(boolean acceptsDelayedFocusGain) {
            mDelayedFocus = acceptsDelayedFocusGain;
            return this;
        }
```

这个方法举个例子说明更容易理解，我们现在播放QQ音乐，这个时候来了一个电话，此时QQ音乐暂停播放，如果打完电话挂断，我们知道正常的逻辑是会继续播放QQ音乐，但如果打电话过程中要播放一个网易云音乐如果setAcceptsDelayedFocusGain（true）那么当挂断电话后，网易云音乐回收一个granted的callback，就可以继续播放网易云音乐了，而不是继续播放QQ音乐。

```java
        public @NonNull Builder setForceDucking(boolean forceDucking) {
            mA11yForceDucking = forceDucking;
            return this;
        }
```

这个不是很常用，只有当AudioAttributes的usage是USAGE_ASSISTANCE_ACCESSIBILITY以及申请的是AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK的时候，会强制duck其他音源，这个主要用于无障碍服务中。

AudioFocusRequest的创建方式两种，一种通过构造函数传入所有参数，一种通过builder的方式，设置我们只关心的参数。主要的函数是setFocusGain和setOnAudioFocusChangeListener和setAudioAttributes，其他可根据具体需求设置。以上就这么多，如果有问题欢迎大家一起讨论交流。
