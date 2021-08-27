---
link: https://blog.csdn.net/l328873524/article/details/105189766
title: Android10.0AudioFocus之如何使用（一）
description: 前言对于音频焦点，很多人会感到很陌生，也很迷惑，不清楚音频焦点到底处理什么的，怎么用。有人说要播放音乐，必须先申请焦点，只有拿到焦点后才能播放音乐，可叶有人说我不申请音频焦点也能播放音乐，因此，今天我们就来说说到底什么是音频焦点，正文AudioFocus机制实在Android2.2引入的，当初是为了协调各应用之间竞争Audio资源的问题，举个简单例子QQ音乐要播放音乐，优酷要播放视频。对于手...
keywords: Android10.0AudioFocus之如何使用（一）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-03-30T14:59:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=27 sentences=77, words=328
---
###### 前言

对于音频焦点，很多人会感到很陌生，也很迷惑，不清楚音频焦点到底处理什么的，怎么用。有人说要播放音乐，必须先申请焦点，只有拿到焦点后才能播放音乐，可也有人说我不申请音频焦点也能播放音乐，因此，今天我们就来说说到底什么是音频焦点。

###### 正文

AudioFocus机制实在Android2.2引入的，当初是为了协调各应用之间竞争Audio资源的问题，举个简单例子QQ音乐要播放音乐，优酷要播放视频。对于手机上的这两个应用，如果视频和音乐同时播放，效果可想而知，那么他们之间怎么实现互斥播放的呢，当然实现的方式很多，广播 binder的进程间通信等，但你觉得QQ音乐会告诉优酷你接下我的广播，或者优酷告诉QQ音乐你bind下我，如果在加入一个网易云音乐，爱奇艺视频，显然是不可以的，谷歌爸爸显然又不可能让大家胡闹下去，因为好的用户体验还是很重要的嘛，因此这个时候AudioFocus就出现了。
谷歌爸爸说我来制定一套游戏规则，大家遵守规则就可以愉快的一起玩耍了，但既然只是规则，那么就有遵守游戏规则的好孩子以及不遵守游戏规则的好孩子。
遵不遵守游戏规则都是可以一起玩耍的，这就回到了我们开始说的问题。有人说要播放音乐，必须先申请焦点，只有拿到焦点后才能播放音乐（遵守游戏规则的好孩子），可也有人说我不申请音频焦点也能播放音乐（不遵守游戏规则的好孩子）
说到这我想这回对音频焦点都有了一个初步的认时，既然是规则，显然是个弱管理。也就是说如果你想播放，不管拿不拿得到音频焦点，都是可以播放的。影响的只是体验效果，不是播放问题。这个一定要搞懂。
废话连篇的说了好多，那么如何使用呢？过时的使用方法就不说了，我们只说最新的关于AudioFocus的Api。

```java
package com.example.myapplication;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import androidx.annotation.NonNull;

public class MainActivity extends Activity {

    private AudioManager mAudioManager;
    private AudioFocusRequest mFocusRequest;
    private AudioManager.OnAudioFocusChangeListener mListener;
    private AudioAttributes mAttribute;
    @SuppressLint("HandlerLeak")
    private Handler mHandler = new Handler() {
        @Override
        public void handleMessage(@NonNull Message msg) {
            super.handleMessage(msg);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        mAudioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        mListener = new AudioManager.OnAudioFocusChangeListener() {
            @Override
            public void onAudioFocusChange(int focusChange) {
                switch (focusChange) {
                    case AudioManager.AUDIOFOCUS_GAIN:

                        break;
                    case AudioManager.AUDIOFOCUS_LOSS:

                        break;
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:

                        break;
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:

                        break;
                    default:
                        break;
                }

            }
        };

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            mAttribute = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build();
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            mFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setWillPauseWhenDucked(true)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener(mListener, mHandler)
                    .setAudioAttributes(mAttribute)
                    .build();
        }
    }

    private void requestAudioFocus() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            int ret = mAudioManager.requestAudioFocus(mFocusRequest);
            if (ret == AudioManager.AUDIOFOCUS_REQUEST_FAILED) {

            } else if (ret == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {

            } else if (ret == AudioManager.AUDIOFOCUS_REQUEST_DELAYED) {

            }
        }
    }

    private void abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            mAudioManager.abandonAudioFocusRequest(mFocusRequest);
        }

    }
}

```

以上就是App使用AudioFocus的一个简单demo，那么我们在使用的时候申请一个什么类型的焦点呢？有几个值的含义是一定要明确的：
AUDIOFOCUS_GAIN：长时间获取焦点，一般用于音视频。
AUDIOFOCUS_GAIN_TRANSIENT:短暂获得，一般用于电话，语音助理等
AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK：混音，一般用于导航
AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE:（android后加的）与AUDIOFOCUS_GAIN_TRANSIENT类似，表示一个短暂的获取焦点，一般用于语音识别什么的，很少用。
既然提到了电话这里先吐槽下谷歌做的音频焦点，那是真的烂，因此才会有那么多的厂商来定制音频焦点这块，本来一个requestAudioFocus就可以了，但发现电话时好像不应该被其他应用抢去焦点，那可咋整，哦，加个接口吧，于是乎 public void requestAudioFocusForCall(int streamType, int durationHint) 来了，requestAudioFocus（AudioFocusRequest requset）被更新来更新去， requestAudioFocusForCall(int streamType, int durationHint) 貌似出了之后发现不是很好在就一直没有更新过，requestAudioFocusForCall优先级最高，也不需要返回值，方法执行成功与否也不知道，对应abandonAudioFocusForCall()也是简单粗暴。其实个人觉得requestAudioFocusForCall(int streamType, int durationHint)这个durationHint基本可以写死AUDIOFOCUS_GAIN_TRANSIENT，这样岂不更简单粗暴。
说的有点跑题，综上，根据这些值含义，我们基本知道了我们要申请什么样的音频焦点，下一篇说一下申请每一种音频焦点对应的listener会给的callback都有哪些，以及从源码角度来分析整个音频焦点的原理。

###### 总结

其实音频焦点要说的还有很多，包括Car上的Audio，从下篇开始，我们就从源码角度一点一点分析其原理。
归根结底音频焦点本身是一种弱管理，只是规则的制订，至于是否遵守是应用自身行为，就像红绿灯，如果你非要闯红灯，非要逆行，音频焦点本身控制不了交通，最终依赖车辆自身行为。就是这个道理。
希望这篇文章，对于新接触Android音频焦点的朋友有一点点的帮助。
