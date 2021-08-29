---
link: https://blog.csdn.net/u013377887/article/details/118859192
title: Understanding Audio Focus (Part 3 / 3)
description: The goal of this series of articles is to give you a deep understanding of what audio focus is, why it’s important to deliver a good media UX, and how to use it. This is the final part of the series that includes:The importance of being a good media citi
keywords: Understanding Audio Focus (Part 3 / 3)
author: Sunnie_ge Csdn认证博客专家 Csdn认证企业博客 码龄8年 暂无认证
date: 2021-07-17T08:54:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=53 sentences=139, words=1812
---
The goal of this series of articles is to give you a deep understanding of what audio focus is, why it's important to deliver a good media UX, and how to use it. This is the final part of the series that includes:

1. [The importance of being a good media citizen and the most common Audio Focus use cases](https://medium.com/@nazmul/audio-focus-1-6b32689e4380)
2. [Other use cases where Audio Focus is important to your media app's UX](https://medium.com/@nazmul/audio-focus-2-42244043863a)
3. Three steps to implementing Audio Focus in your app (**_this article_**)

If you don't handle audio focus properly, the following diagram depicts what your user might experience on their phone.

![](https://img-blog.csdnimg.cn/img_convert/bee731da3a1670c2aa12470e29b62c3f.png)

Now that you know the importance of your app being a good media citizen for the user to have a good media experience on their phone, let's go thru steps that will allow your app to handle audio focus properly.

Before jumping into the code, the following diagram summarizes the steps that we are going to take to implement audio focus in your app.

![](https://img-blog.csdnimg.cn/img_convert/dba9c4e49acfef8752a4b4900da1febf.png)

# Step 1 : Make the focus request

The first step in getting audio focus is making the request of the Android system to acquire it. Keep in mind that just because you have made the request doesn't mean that it will be granted. In order to make the request to acquire audio focus you have to declare your "intention" to the system. Here are some examples.

* Is your app a media player or podcast player that will hold the audio focus for an indefinite period of time (as long as the user choose to play audio from your app)? This is `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN">AUDIOFOCUS_GAIN</a>`.

* Or does your app temporarily need audio focus (with the option to duck), since it needs to play an audio notification, or a turn by turn spoken direction, or it needs to record audio from the user for a short period of time? This is `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK">AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK</a>`.

* Does your app temporarily need audio focus (but for an unknown duration, without the option to duck) like a phone app would once a call is connected? This is `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN_TRANSIENT">AUDIOFOCUS_GAIN_TRANSIENT</a>`.

* Does your app temporarily need audio focus (for an unknown duration, during which no other sounds should be generated) since it needs to record audio like a voice memo app? This is `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE">AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE</a>`.

On Android O and later you have to create an `<a href="https://developer.android.com/reference/android/media/AudioFocusRequest.html">AudioFocusRequest</a>` object (using a `<a href="https://developer.android.com/reference/android/media/AudioFocusRequest.Builder.html">builder</a>`). And in this object you will have to specify how long your app needs to acquire audio focus. The following code snippet declares the intention to permanently acquire audio focus from the system.

```
AudioManager mAudioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);AudioAttributes mAudioAttributes =
       new AudioAttributes.Builder()
               .setUsage(AudioAttributes.USAGE_MEDIA)
               .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
               .build();AudioFocusRequest mAudioFocusRequest =
       new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
               .setAudioAttributes(mAudioAttributes)
               .setAcceptsDelayedFocusGain(true)
               .setOnAudioFocusChangeListener(...) // Need to implement listener
               .build();int focusRequest = mAudioManager.requestAudioFocus(mAudioFocusRequest);switch (focusRequest) {
   case AudioManager.AUDIOFOCUS_REQUEST_FAILED:
       // don't start playback
   case AudioManager.AUDIOFOCUS_REQUEST_GRANTED:
       // actually start playback
}
```

Notes on the code:

1. The `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN">AudioManager.AUDIOFOCUS_GAIN</a>` is what requests permanent audio focus from the system. You can also pass it it other int values, such as `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN_TRANSIENT">AUDIOFOCUS_GAIN_TRANSIENT</a>`, or `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK">AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK</a>` if you just wanted temporary audio focus.

2. You have to pass a `<a href="https://developer.android.com/reference/android/media/AudioManager.OnAudioFocusChangeListener.html">AudioManager.OnAudioFocusChangeListener</a>` implementation to the `<a href="https://developer.android.com/reference/android/media/AudioFocusRequest.Builder.html#setOnAudioFocusChangeListener%28android.media.AudioManager.OnAudioFocusChangeListener%29">setOnAudioFocusChangeListener()</a>` method. This is the part of your code that will deal with audio focus changes which are driven by events happening in the system. These might be started from user interactions in other apps. For example, your app might have gained permanent audio focus, but then the user launches another app which takes it away. This listener is where your app would have to deal with this focus loss.

3. Once you have created the `<a href="https://developer.android.com/reference/android/media/AudioFocusRequest.html">AudioFocusRequest</a>` object, you can now use it in order to ask the `AudioManager` for audio focus by calling `<a href="https://developer.android.com/reference/android/media/AudioManager.html#requestAudioFocus%28android.media.AudioFocusRequest%29">requestAudioFocus(&#x2026;)</a>`. This will return an integer value representing whether your audio focus request was granted or not. Only if that value is `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_REQUEST_GRANTED">AUDIOFOCUS_REQUEST_GRANTED</a>` should you start playback immediately. And if it's `<a href="https://developer.android.com/reference/android/media/AudioManager.html#AUDIOFOCUS_REQUEST_FAILED">AUDIOFOCUS_REQUEST_FAILED</a>`, then the system has denied your app acquisition of audio focus in that moment.

On Android N and earlier you can declare this intention without using the `AudioFocusRequest` object as shown below. You still have to implement `AudioManager.OnAudioFocusChangeListener`. Here's the equivalent code to the snippet above.

```
AudioManager mAudioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);int focusRequest = mAudioManager.requestAudioFocus(..., // Need to implement listener
       AudioManager.STREAM_MUSIC,
       AudioManager.AUDIOFOCUS_GAIN);switch (focusRequest) {
   case AudioManager.AUDIOFOCUS_REQUEST_FAILED:
       // don't start playback
   case AudioManager.AUDIOFOCUS_REQUEST_GRANTED:
       // actually start playback
}
```

Next, we have to implement the `AudioManager.OnAudioFocusChangeListener` so that the app can react to changes in audio focus gain and loss.

# Step 2 : Respond to audio focus state changes

Once audio focus has been granted to your app (whether this is temporary or permanent) it can change at any time. And your app must react to this change. This is what happens in your `OnAudioFocusChangeListener` implementation.

The following code snippet contains an implementation of this interface for an app that plays audio. And it handles ducking for transient audio focus loss. It also handles audio focus change due to the user pausing playback, vs another app ([like the Google Assistant](https://developer.android.com/guide/topics/media-apps/interacting-with-assistant.html)) causing transient audio focus loss.

```
private final class AudioFocusHelper
        implements AudioManager.OnAudioFocusChangeListener {private void abandonAudioFocus() {
        mAudioManager.abandonAudioFocus(this);
    }@Override
    public void onAudioFocusChange(int focusChange) {
        switch (focusChange) {
            case AudioManager.AUDIOFOCUS_GAIN:
                if (mPlayOnAudioFocus && !isPlaying()) {
                    play();
                } else if (isPlaying()) {
                    setVolume(MEDIA_VOLUME_DEFAULT);
                }
                mPlayOnAudioFocus = false;
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                setVolume(MEDIA_VOLUME_DUCK);
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                if (isPlaying()) {
                    mPlayOnAudioFocus = true;
                    pause();
                }
                break;
            case AudioManager.AUDIOFOCUS_LOSS:
                mAudioManager.abandonAudioFocus(this);
                mPlayOnAudioFocus = false;
                stop();
                break;
        }
    }
}
```

The app should behave differently when the user initiates the pause of playback, from when another app requests transient audio focus and playback is paused as a result (instead of just ducking). When the user initiates pausing playback, your app should abandon audio focus. However, if your app pauses playback in response to a transient loss of audio focus, then it should not abandon audio focus. Here are some use cases to illustrate this.

Let's say you have an audio playback app that plays audio in the background.

1. When the user presses play, your app requests permanent audio focus. Let's say that it's granted audio focus by the system.

2. Now they long press the home button and it starts the Google Assistant. The Assistant will request to gain transient audio focus.

3. Once the system grants this to the Assistant, your `OnAudioFocusChangeListener` will get a `AUDIOFOCUS_LOSS_TRANSIENT` event. And here, you would pause playback, since the Assistant needs to record audio.

4. Once the Assistant is done, it will abandon its audio focus, and your app will be granted `AUDIOFOCUS_GAIN` in the `OnAudioFocusChangeListener`. This is where you have to decide whether to resume playback or not. And this is what the `mPlayOnAudioFocus` flag does in the code snippet above.

The following code snippet is what the user initiated pause method might look like in this audio player app.

```
public final void pause() {
   if (!mPlayOnAudioFocus) {
       mAudioFocusHelper.abandonAudioFocus();
   }
  onPause();
}
```

As you can see it abandons audio focus when the user initiates pausing playback, but not when other apps cause it to happen (when they acquire `AUDIOFOCUS_GAIN_TRANSIENT`).

## Ducking vs pausing on transient audio focus loss

You can choose to pause playback or temporarily reduce the volume of your audio playback in the `OnAudioFocusChangeListener`, depending on what UX your app needs to deliver. Android O supports auto ducking, where the system will reduce the volume of your app automatically without you having to write any extra code. In your `OnAudioFocusChangeListener`, just ignore the `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` event.

In Android N and earlier, you have to implement ducking yourself (as shown in the code snippet above).

## Delayed gain

Android O introduced the concept of delayed audio focus gain. In order to implement this, when you request audio focus, you can get a `AUDIOFOCUS_REQUEST_DELAYED` result, as shown below.

```
public void requestPlayback() {
    int audioFocus = mAudioManager.requestAudioFocus(mAudioFocusRequest);
    switch (audioFocus) {
        case AudioManager.AUDIOFOCUS_REQUEST_FAILED:
            ...

        case AudioManager.AUDIOFOCUS_REQUEST_GRANTED:
            ...

        case AudioManager.AUDIOFOCUS_REQUEST_DELAYED:
            mAudioFocusPlaybackDelayed = true;
    }
}
```

In your `OnAudioFocusChangeListener` implementation, you will then have to check for the `mAudioFocusPlaybackDelayed` variable when you respond to `AUDIOFOCUS_GAIN`, as shown below.

```
private void onAudioFocusChange(int focusChange) {
   switch (focusChange) {
       case AudioManager.AUDIOFOCUS_GAIN:
           logToUI("Audio Focus: Gained");
           if (mAudioFocusPlaybackDelayed || mAudioFocusResumeOnFocusGained) {
               mAudioFocusPlaybackDelayed = false;
               mAudioFocusResumeOnFocusGained = false;
               start();
           }
           break;
       case AudioManager.AUDIOFOCUS_LOSS:
           mAudioFocusResumeOnFocusGained = false;
           mAudioFocusPlaybackDelayed = false;
           stop();
           break;
       case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
           mAudioFocusResumeOnFocusGained = true;
           mAudioFocusPlaybackDelayed = false;
           pause();
           break;
       case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
           pause();
           break;
   }
}
```

# Step 3 : Remember to abandon audio focus

When your app has completed playing it's audio, then it should abandon audio focus by calling `<a href="https://developer.android.com/reference/android/media/AudioManager.html#abandonAudioFocus%28android.media.AudioManager.OnAudioFocusChangeListener%29">AudioManager.abandonAudioFocus(&#x2026;)</a>`. In the previous step we ran into the situation of an app abandoning audio focus when the user initiates pausing playback, but the app retaining audio focus when it's interrupted temporarily by other apps.

# Code samples

## Gist that you can use in your app

You can find 3 classes in this [GitHub gist](https://gist.github.com/nic0lette/c360dd353c451d727ea017890cbaa521) that covers audio focus code that you might be able to use in your apps.

* `<a href="https://gist.github.com/nic0lette/c360dd353c451d727ea017890cbaa521#file-audiofocusrequestcompat-java">AudioFocusRequestCompat</a>` — Use this class to describe the type of audio focus that your app needs.

* `<a href="https://gist.github.com/nic0lette/c360dd353c451d727ea017890cbaa521#file-audiofocushelper-java">AudioFocusHelper</a>` — This class actually handles audio focus for you. You can include it in your app, but you have to make sure that your audio playback service uses the interface below.

* `<a href="https://gist.github.com/nic0lette/c360dd353c451d727ea017890cbaa521#file-audiofocusawareplayer-java">AudioFocusAwarePlayer</a>` — This interface should be implemented by the service that manages your media player (`MediaPlayer` or `ExoPlayer`) and it will allow the `AudioFocusHelper` class to make it work with audio focus.

## Complete code sample

The `<a href="https://github.com/googlesamples/android-MediaBrowserService">android-MediaBrowserService</a>` sample showcases how you can handle audio focus in an Android app that uses the `MediaPlayer` to actually play audio in the background. It also uses `MediaSession`.

The sample has a `<a href="https://github.com/googlesamples/android-MediaBrowserService/blob/master/app/src/main/java/com/example/android/mediasession/service/PlayerAdapter.java">PlayerAdapter</a>` class that showcases audio focus best practices. Please take a look at at the `pause()` and `onAudioFocusChange(int)` method implementations.

# Test your code

Once you've implemented audio focus in your app, you can use the Android Media Controller Tool to test how your app reacts to focus gain and loss. You can get it on [GitHub](https://github.com/googlesamples/android-media-controller#audio-focus).

![](https://img-blog.csdnimg.cn/img_convert/4a726a91aab5cdd7d941c139799342cc.png)

# Android Media Resources

* [Sample code — MediaBrowserService](https://github.com/googlesamples/android-MediaBrowserService)
* [Sample code — MediaSession Controller Test (with support for audio focus testing)](https://github.com/googlesamples/android-media-controller)
* [Understanding MediaSession](https://medium.com/google-developers/understanding-mediasession-part-1-3-e4d2725f18e4)
* [Media API Guides — Media Apps Overview](https://developer.android.com/guide/topics/media-apps/media-apps-overview.html)
* [Media API Guides — Working with a MediaSession](https://developer.android.com/guide/topics/media-apps/working-with-a-media-session.html)
* [Building a simple audio playback app using MediaPlayer](https://medium.com/google-developers/building-a-simple-audio-app-in-android-part-1-3-c14d1a66e0f1)
