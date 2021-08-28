---
link: https://blog.csdn.net/l328873524/article/details/106044958
title: Android10.0CarAudioZone（五）
description: 前言关于CarAudioZone的部分已经说的七七八八了，但我们一直都还有个疑问，既然CarAudioZone分了不同的zone来实现各自的声音路由、音量调节、音频焦点控制等，那么对于应用又是如何才区分使用的是哪个zone的呢，那么就是今天要说的uid正文说到uid，先说下Android的几个概念pid 是process进程iduid 是user 用户idtid（是thead线程id每个应用都有一个uid，和n个pid，以及n个tid，那么三个id的获取方式呢android.os.Proc
keywords: Android10.0CarAudioZone（五）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-05-12T15:40:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=47 sentences=74, words=570
---
关于CarAudioZone的部分已经说的七七八八了，但我们一直都还有个疑问，既然CarAudioZone分了不同的zone来实现各自的声音路由、音量调节、音频焦点控制等，那么对于应用又是如何才区分使用的是哪个zone的呢，那么就是今天要说的uid

说到uid，先说下Android的几个概念
pid 是process进程id
uid 是user 用户id
tid（是thead线程id
每个应用都有一个uid，和n个pid，以及n个tid，那么三个id的获取方式呢

```java

android.os.Process.myPid();

android.os.Process.myTid();

android.os.Process.myUid();

```

android会指定一些系统应用或服务的uid，比如system server的uid是1000，一般app的应用的uid都是1000多的一个值。
关于uid这里就不多说了，我们看下uid在CarAudio中的应用，先来看下CarAudioManger的Api

```java
    public boolean setZoneIdForUid(int zoneId, int uid) {
        try {
            return mService.setZoneIdForUid(zoneId, uid);
        } catch (RemoteException e) {
            throw e.rethrowFromSystemServer();
        }
    }
```

直接调到CarAudioService中了，

```java
    public boolean setZoneIdForUid(int zoneId, int uid) {
        enforcePermission(Car.PERMISSION_CAR_CONTROL_AUDIO_SETTINGS);
        synchronized (mImplLock) {
            Log.i(CarLog.TAG_AUDIO, "setZoneIdForUid Calling uid "
                    + uid + " mapped to : "
                    + zoneId);

            Integer currentZoneId = mUidToZoneMap.get(uid);
            ArrayList<AudioFocusInfo> currentFocusHoldersForUid = new ArrayList<>();
            ArrayList<AudioFocusInfo> currentFocusLosersForUid = new ArrayList<>();
            if (currentZoneId != null) {
                currentFocusHoldersForUid = mFocusHandler.getAudioFocusHoldersForUid(uid,
                        currentZoneId.intValue());
                currentFocusLosersForUid = mFocusHandler.getAudioFocusLosersForUid(uid,
                        currentZoneId.intValue());
                if (!currentFocusHoldersForUid.isEmpty() || !currentFocusLosersForUid.isEmpty()) {

                    mFocusHandler.transientlyLoseInFocusInZone(currentFocusLosersForUid,
                            currentZoneId.intValue());

                    mFocusHandler.transientlyLoseInFocusInZone(currentFocusHoldersForUid,
                            currentZoneId.intValue());
                }
            }

            if (checkAndRemoveUidLocked(uid)) {
                if (setZoneIdForUidNoCheckLocked(zoneId, uid)) {

                    if (!currentFocusLosersForUid.isEmpty()) {
                        regainAudioFocusLocked(currentFocusLosersForUid, zoneId);
                    }

                    if (!currentFocusHoldersForUid.isEmpty()) {
                        regainAudioFocusLocked(currentFocusHoldersForUid, zoneId);
                    }
                    return true;
                }
            }
            return false;
        }
    }
```

代码有点长，但是逻辑不是很复杂，我们一点一点来分析。mUidToZoneMap是表示uid与zoneid的map表，即每个uid对应在哪个音区中，currentFocusHoldersForUid 和currentFocusLosersForUid这俩list是来获取当前uid在hoder音频焦点map和loser音频焦点map中的焦点信息集合（这俩集合说到音频焦点交互的时候再细说），具体来看一下getAudioFocusHoldersForUid在CarZonesAudioFocus.java中

```java
    ArrayList<AudioFocusInfo> getAudioFocusHoldersForUid(int uid, int zoneId) {
        CarAudioFocus focus = mFocusZones.get(zoneId);
        return focus.getAudioFocusHoldersForUid(uid);
    }
```

根据zoneId先找到对应的音区，然后对应到该音区的CarAudioFocus 获取getAudioFocusHoldersForUid

```java
    ArrayList<AudioFocusInfo> getAudioFocusHoldersForUid(int uid) {
        return getAudioFocusListForUid(uid, mFocusHolders);
    }
```

这里的mFocusHolders是我们在做音频焦点优先级处理的时候，维护的一个map，这个和MediaFocusControl中那个mFocusStack不同，mFocusStack存的是FocusRequester，而且使用stack来存储的，而这里使用map存储的一个clientId与FocusEntry对应关系，FocusEntry中最重要的一个就是AudioFocusInfo。关于mFocusHolders的存储等我们说到音频焦点优先级处理的时候再具体说。

```java
    private ArrayList<AudioFocusInfo> getAudioFocusListForUid(int uid,
            HashMap<String, FocusEntry> mapToQuery) {
        ArrayList<AudioFocusInfo> matchingInfoList = new ArrayList<>();
        for (String clientId : mapToQuery.keySet()) {
            AudioFocusInfo afi = mapToQuery.get(clientId).mAfi;
            if (afi.getClientUid() == uid) {
                matchingInfoList.add(afi);
            }
        }
        return matchingInfoList;
    }
```

这里遍历mapToQuery也就是mFocusHolders中找出对应uid的AudioFocusInfo返回，同理我们又拿到了currentFocusLosersForUid 。拿到之后做了一个remove即transientlyLoseInFocusInZone

```java
    void transientlyLoseInFocusInZone(@NonNull ArrayList<AudioFocusInfo> afiList,
            int zoneId) {
        CarAudioFocus focus = mFocusZones.get(zoneId);

        for (AudioFocusInfo info : afiList) {
            focus.removeAudioFocusInfoAndTransientlyLoseFocus(info);
        }
    }
```

又到了CarAudioFocus 中

```java
    void removeAudioFocusInfoAndTransientlyLoseFocus(AudioFocusInfo afi) {

        FocusEntry deadEntry = removeFocusEntry(afi);

        if (deadEntry != null) {

            sendFocusLoss(deadEntry, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT);

            removeFocusEntryAndRestoreUnblockedWaiters(deadEntry);
        }
    }
```

然后回到CarAudioService的setZoneIdForUid中checkAndRemoveUidLocked

```java
    private boolean checkAndRemoveUidLocked(int uid) {
        Integer zoneId = mUidToZoneMap.get(uid);
        if (zoneId != null) {
            Log.i(CarLog.TAG_AUDIO, "checkAndRemoveUid removing Calling uid "
                    + uid + " from zone " + zoneId);
            if (mAudioPolicy.removeUidDeviceAffinity(uid)) {

                mUidToZoneMap.remove(uid);
                return true;
            }

            Log.w(CarLog.TAG_AUDIO,
                    "checkAndRemoveUid Failed remove device affinity for uid "
                            + uid + " in zone " +  zoneId);
            return false;
        }
        return true;
    }
```

这里涉及一个mAudioPolicy.removeUidDeviceAffinity(uid)，这里先不细说了，这个是在声音播放的时候选择声音在哪个分区，通过Audiopolicy注册到native的AudioPlocyManager的AudioPolicyMix中做声音路由的，这里主要是 mUidToZoneMap.remove(uid)，将uid从map中移除，之后再setZoneIdForUidNoCheckLocked

```java
    private boolean setZoneIdForUidNoCheckLocked(int zoneId, int uid) {
        Log.d(CarLog.TAG_AUDIO, "setZoneIdForUidNoCheck Calling uid "
                + uid + " mapped to " + zoneId);

        if (mAudioPolicy.setUidDeviceAffinity(uid, mCarAudioZones[zoneId].getAudioDeviceInfos())) {

            mUidToZoneMap.put(uid, zoneId);
            return true;
        }
        Log.w(CarLog.TAG_AUDIO, "setZoneIdForUidNoCheck Failed set device affinity for uid "
                + uid + " in zone " + zoneId);
        return false;
    }
```

这里mAudioPolicy.setUidDeviceAffinity(uid, mCarAudioZones[zoneId].getAudioDeviceInfos())也先不说，后续在讲， 然后将uid和zoneId放入map。最后再regainAudioFocusLocked(currentFocusLosersForUid, zoneId)

```java
    void regainAudioFocusLocked(ArrayList<AudioFocusInfo> afiList, int zoneId) {
        for (AudioFocusInfo info : afiList) {
            if (mFocusHandler.reevaluateAndRegainAudioFocus(info)
                    != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.i(CarLog.TAG_AUDIO,
                        " Focus could not be granted for entry "
                                + info.getClientId()
                                + " uid " + info.getClientUid()
                                + " in zone " + zoneId);
            }
        }
    }
```

再来复归焦点
int reevaluateAndRegainAudioFocus(AudioFocusInfo afi) {
CarAudioFocus focus = getFocusForAudioFocusInfo(afi);
return focus.reevaluateAndRegainAudioFocus(afi);
}
这里看似没啥，其实这个音频焦点的交付已经转到我们设置的uid对应的音区了

```java
    int reevaluateAndRegainAudioFocus(AudioFocusInfo afi) {
        int results = evaluateFocusRequest(afi);

        if (results == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            return dispatchFocusGained(afi);
        }
        return results;
    }
```

最后新的音区中重新来做音频焦点的交互。

简单总结一下，主要是关于setZoneIdForUid的这个方法，他有两个功能，一个是将AudioFocus根据不同的zone，实现各自独立的音频焦点的交互。另一个功能是将uid与之对应的device注册下去实现音频路由在不同分区的实现（比如我们都播放音乐我们可以根据uid来指定我们的音乐播放到哪个音区中）
关于AudioFocus这里后续没有细说，因为涉及篇幅较大，后续单独分析。这里主要我们在set uid的时候，根据set前uid所在分区找到focus的集合，然后在之前的分区中移除这些uid对应的audiofocus，如果focus在之前分区中是holder的即actived的，那么通知其失去。移除后当我们在设置uid对应的新的音区时，在把移除的这些focus加入到新的音区，如果在新的音区是loser的状态，则不回调给应用了，因为在之前音区移除的时候已经通知lose了，如果在新的音区是granted的，则通知其又获取了focus，不得不说谷歌在这里处理的真的很好，对于已经是在使用中的音频焦点，重新设置分区，即不会扰乱设置前分区中audiofocus的逻辑，也不会打乱从新set后的音区中AudioFocus的逻辑。而且每一种可能处理的都十分完美。
谷歌在Android10.0中CarAudioZone的设计，虽然代码逻辑还有的优化，但整体功能真的太棒了。
最后欢迎大家交流沟通
