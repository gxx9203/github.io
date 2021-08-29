---
link: https://blog.csdn.net/u013377887/article/details/118859127
title: Understanding Audio Focus (Part 1 / 3)
description: Many apps on your Android phone can play audio simultaneously. While the Android operating system mixes all audio streams together, it can be very disruptive to a user when multiple apps are playing audio at the same time. This results in the user having a
keywords: Understanding Audio Focus (Part 1 / 3)
author: Sunnie_ge Csdn认证博客专家 Csdn认证企业博客 码龄8年 暂无认证
date: 2021-07-17T08:52:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=25 sentences=41, words=814
---
Many apps on your Android phone can play audio simultaneously. While the Android operating system mixes all audio streams together, it can be very disruptive to a user when multiple apps are playing audio at the same time. This results in the user having a poor experience on their phone. To deliver a good UX, Android provides an [API](https://developer.android.com/guide/topics/media-apps/audio-focus.html) that lets apps share _audio focus_, where only one app can hold audio focus at a time.

The goal of this series of articles is to give you a deep understanding of what audio focus is, why it's important to delivering a good media UX, and how to use it. This is the first part of a three part series that includes:

1. The importance of being a good media citizen and the most common Audio Focus use cases (**_this article_**)
2. [Other use cases where Audio Focus is important to your media app's UX](https://medium.com/@nazmul/audio-focus-2-42244043863a)
3. [Three steps to implementing Audio Focus in your app](https://medium.com/@nazmul/audio-focus-3-cdc09da9c122)

Audio focus is cooperative and relies on apps to comply with the audio focus guidelines. The system does not enforce the rules. If an app wants to continue to play loudly even after losing audio focus, nothing can prevent that. This however results in a bad user experience for the user on the phone and there's a good chance they will uninstall an app that misbehaves in this way.

Here are some scenarios where audio focus comes into play. Assume that the user has launched your app and it's playing audio.

When your app needs to output audio, it should request audio focus. Only after it has been granted focus, it should play sound.

# Use case 1 — While playing audio from your app, the user starts another media player app and starts playback in that app

## What happens if your app doesn't handle audio focus

When the other media app starts playing audio, it overlaps with your app playing audio as well. This results in a bad UX since the user won't be able to hear audio from either app properly.

![](https://img-blog.csdnimg.cn/img_convert/90e0db0282bd0d45747e9e644e9a8973.png)

## **_What should happen with your app handling audio focus_**

When the other media app starts playback, it requests permanent audio focus. Once granted by the system, it will begin playback. Your app needs to respond to a permanent loss of audio focus by stopping playback so the user will only hear audio the other media app.

![](https://img-blog.csdnimg.cn/img_convert/df2142b249267b858ac48c3794c4f8e4.png)

Now, if the user then tries to start playback in your app, then your app will once again request permanent audio focus. And only once this focus is granted should your app start playback of audio. The other app will have to respond to the permanent loss of audio focus by stopping its playback.

# Use case 2 — An incoming phone call arrives while your app is playing audio

## **_What happens if your app doesn't handle audio focus_**

When the phone starts to ring, the user will hear audio from your app in addition to the ringer, which is not a good UX. If they choose to decline the call, then your audio will continue to play. If they choose to accept the call, then the audio will play along with the phone audio. When they are done with the call, then your app will not automatically resume playback, which is also not a good UX.

![](https://img-blog.csdnimg.cn/img_convert/08896a27cba7fc3ed000b25832e2bbcb.png)

## **_What should happen with your app handling audio focus_**

When the phone rings (and the user hasn't answered yet), your app should respond to a transient loss of audio focus with the option to duck (as this is being requested by the phone app). It should respond by either reducing the volume to about 20% (called _ducking_), or pause playback all together (if it's a podcast or other spoken word type of app).

* If the user declines the call, then your app should react to the gain of audio focus by restoring the volume, or resuming playback.

* If the user accepts the call, the system will send you a loss of audio focus (without the option to _duck_). Your app should pause playback in response. When they're finished with the call, your app should react to the gain of audio focus by resuming playback of audio at full volume.

![](https://img-blog.csdnimg.cn/img_convert/5b5fea7f85d9de1dd3a0c1ceb7b51012.png)

# Summary

When your app needs to output audio, it should request audio focus. Only after it has been granted focus, it should play sound. However, after you acquire audio focus you may not be able to keep it until your app has completed playing audio. Another app can request focus, which preempts your hold on audio focus. In this case your app should either pause playing or lower its volume to let users hear the new audio source more easily.

To learn more about the other use cases where audio focus comes into play in your app, read the [second article in this series](https://medium.com/@nazmul/audio-focus-2-42244043863a).
