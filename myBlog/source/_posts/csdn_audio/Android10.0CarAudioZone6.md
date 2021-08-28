---
link: https://blog.csdn.net/l328873524/article/details/106203615
title: Android10.0CarAudioZone（六）
description: 前言我们之前分析了CarAudioZone的比较核心的一个Api，setZoneIdForUid，我们知道通过将uid与zoneId绑定到一起的方式，实现多音区的功能。即不同音区的AudioFocus管理互不影响，我们的媒体也可以想播放在哪个Zone中就播放在哪个zone中，只要我们配置好car_audio_configuration.xml，以及设置对应的setZoneIdForUid即可。上一篇分析了AudioFocus在CarAudioZone中如何实现不同音区管理的，那么今天我们继续分析下播放流又
keywords: Android10.0CarAudioZone（六）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-05-20T16:26:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=52 sentences=85, words=859
---
我们之前分析了CarAudioZone的比较核心的一个Api，setZoneIdForUid，我们知道通过将uid与zoneId绑定到一起的方式，实现多音区的功能。即不同音区的AudioFocus管理互不影响，我们的媒体也可以想播放在哪个Zone中就播放在哪个zone中，只要我们配置好car_audio_configuration.xml，以及设置对应的setZoneIdForUid即可。上一篇分析了AudioFocus在CarAudioZone中如何实现不同音区管理的，那么今天我们继续分析下播放流又是如何控制的，即播放流的一个路由策略

我们知道在我们对上层的应用调用setZoneIdForUid的时候，我们会调用到mAudioPolicy.setUidDeviceAffinity(uid, mCarAudioZones[zoneId].getAudioDeviceInfos())，关于这个调用的逻辑可查看下[Android10.0CarAudioZone（五）](https://blog.csdn.net/l328873524/article/details/106044958)，这里也是先简单分析一下这几个参数都是做什么的，udi，是上层应用传入的应用的uid，我们知道zoneId也是上层应用传入的，这样我们就可以定位到我们要的CarAudioZone，再看下它的getAudioDeviceInfos

```java
    List<AudioDeviceInfo> getAudioDeviceInfos() {
        final List<AudioDeviceInfo> devices = new ArrayList<>();
        for (CarVolumeGroup group : mVolumeGroups) {
            for (int busNumber : group.getBusNumbers()) {
                devices.add(group.getCarAudioDeviceInfoForBus(busNumber).getAudioDeviceInfo());
            }
        }
        return devices;
    }
```

其实拿的就是我们解析car_audio_configuration.xml中，每个zone里group下所有的device的集合，拿到这个devices后与uid一同传给了AudioPolicy的setUidDeviceAffinity

```java
    public boolean setUidDeviceAffinity(int uid, @NonNull List<AudioDeviceInfo> devices) {
        if (devices == null) {
            throw new IllegalArgumentException("Illegal null list of audio devices");
        }
        synchronized (mLock) {
            if (mStatus != POLICY_STATUS_REGISTERED) {
                throw new IllegalStateException("Cannot use unregistered AudioPolicy");
            }
            final int[] deviceTypes = new int[devices.size()];
            final String[] deviceAdresses = new String[devices.size()];
            int i = 0;
            for (AudioDeviceInfo device : devices) {
                if (device == null) {
                    throw new IllegalArgumentException(
                            "Illegal null AudioDeviceInfo in setUidDeviceAffinity");
                }

                deviceTypes[i] =
                        AudioDeviceInfo.convertDeviceTypeToInternalDevice(device.getType());

                deviceAdresses[i] = device.getAddress();
                i++;
            }
            final IAudioService service = getService();
            try {
            调用了AudioServe的setUidDeviceAffinity
                final int status = service.setUidDeviceAffinity(this.cb(),
                        uid, deviceTypes, deviceAdresses);
                return (status == AudioManager.SUCCESS);
            } catch (RemoteException e) {
                Log.e(TAG, "Dead object in setUidDeviceAffinity", e);
                return false;
            }
        }
    }
```

我们发现在AudioPolicy了一个封装，主要处理的是deviceTypes，和deviceAdresses，然后继续调用AudioService的setUidDeviceAffinity

```java
    public int setUidDeviceAffinity(IAudioPolicyCallback pcb, int uid,
            @NonNull int[] deviceTypes, @NonNull String[] deviceAddresses) {
        if (DEBUG_AP) {
            Log.d(TAG, "setUidDeviceAffinity for " + pcb.asBinder() + " uid:" + uid);
        }
        synchronized (mAudioPolicies) {

            final AudioPolicyProxy app =
                    checkUpdateForPolicy(pcb, "Cannot change device affinity in audio policy");
            if (app == null) {
                return AudioManager.ERROR;
            }
            if (!app.hasMixRoutedToDevices(deviceTypes, deviceAddresses)) {
                return AudioManager.ERROR;
            }
            return app.setUidDeviceAffinities(uid, deviceTypes, deviceAddresses);
        }
    }
```

我们发现这里有个hasMixRoutedToDevices的检查

```java
        boolean hasMixRoutedToDevices(@NonNull int[] deviceTypes,
                @NonNull String[] deviceAddresses) {
            for (int i = 0; i < deviceTypes.length; i++) {
                boolean hasDevice = false;

                for (AudioMix mix : mMixes) {

                    if (mix.isRoutedToDevice(deviceTypes[i], deviceAddresses[i])) {
                        hasDevice = true;
                        break;
                    }
                }
                if (!hasDevice) {
                    return false;
                }
            }
            return true;
        }
```

这个继续判断mix.isRoutedToDevice(deviceTypes[i], deviceAddresses[i])，我们知道deviceType都是bus，那么就在继续看下AudioMix的这个函数

```java
    public boolean isRoutedToDevice(int deviceType, @NonNull String deviceAddress) {

        if ((mRouteFlags & ROUTE_FLAG_RENDER) != ROUTE_FLAG_RENDER) {
            return false;
        }

        if (deviceType != mDeviceSystemType) {
            return false;
        }

        if (!deviceAddress.equals(mDeviceAddress)) {
            return false;
        }
        return true;
    }
```

从这个isRoutedToDevice的判断看返回ture，那么hasMixRoutedToDevices反回也是ture，回到AudioService中，继续调用AudioPolicyProxy的setUidDeviceAffinities

```java
        int setUidDeviceAffinities(int uid, @NonNull int[] types, @NonNull String[] addresses) {
            final Integer Uid = new Integer(uid);
            int res;

            if (mUidDeviceAffinities.remove(Uid) != null) {
                final long identity = Binder.clearCallingIdentity();

                res = AudioSystem.removeUidDeviceAffinities(uid);
                Binder.restoreCallingIdentity(identity);
                if (res != AudioSystem.SUCCESS) {
                    Log.e(TAG, "AudioSystem. removeUidDeviceAffinities(" + uid + ") failed, "
                            + " cannot call AudioSystem.setUidDeviceAffinities");
                    return AudioManager.ERROR;
                }
            }

            final long identity = Binder.clearCallingIdentity();
            res = AudioSystem.setUidDeviceAffinities(uid, types, addresses);

            Binder.restoreCallingIdentity(identity);
            if (res == AudioSystem.SUCCESS) {

                mUidDeviceAffinities.put(Uid, new AudioDeviceArray(types, addresses));
                return AudioManager.SUCCESS;
            }
            Log.e(TAG, "AudioSystem. setUidDeviceAffinities(" + uid + ") failed");
            return AudioManager.ERROR;
        }
```

这里我们看到通过AudioSystem继续向下调用了，jni的部分略过，直接看AudioSystem中的setUidDeviceAffinities

```cpp
status_t AudioSystem::setUidDeviceAffinities(uid_t uid, const Vector<AudioDeviceTypeAddr>& devices)
{
    const sp<IAudioPolicyService>& aps = AudioSystem::get_audio_policy_service();
    if (aps == 0) return PERMISSION_DENIED;
    return aps->setUidDeviceAffinities(uid, devices);
}
```

调用到了AudioPolicyService

```cpp
status_t AudioPolicyService::setUidDeviceAffinities(uid_t uid,
        const Vector<AudioDeviceTypeAddr>& devices) {
    Mutex::Autolock _l(mLock);
    if(!modifyAudioRoutingAllowed()) {
        return PERMISSION_DENIED;
    }
    if (mAudioPolicyManager == NULL) {
        return NO_INIT;
    }
    AutoCallerClear acc;
    return mAudioPolicyManager->setUidDeviceAffinities(uid, devices);
}
```

在AudioPolicyService中继续调用到AudioPolicyManager

```cpp
status_t AudioPolicyManager::setUidDeviceAffinities(uid_t uid,
        const Vector<AudioDeviceTypeAddr>& devices) {
    ALOGV("%s() uid=%d num devices %zu", __FUNCTION__, uid, devices.size());

    for (size_t i = 0; i < devices.size(); i++) {

        if (!audio_is_output_device(devices[i].mType)) {
            ALOGE("setUidDeviceAffinities() device=%08x is NOT an output device",
                    devices[i].mType);
            return BAD_VALUE;
        }
    }
    status_t res =  mPolicyMixes.setUidDeviceAffinities(uid, devices);
    if (res == NO_ERROR) {

        for (size_t i = 0; i < devices.size(); i++) {
            sp<DeviceDescriptor> devDesc = mHwModules.getDeviceDescriptor(
                            devices[i].mType, devices[i].mAddress, String8(),
                            AUDIO_FORMAT_DEFAULT);
            SortedVector<audio_io_handle_t> outputs;
            if (checkOutputsForDevice(devDesc, AUDIO_POLICY_DEVICE_STATE_AVAILABLE,
                    outputs) != NO_ERROR) {
                ALOGE("setUidDeviceAffinities() error in checkOutputsForDevice for device=%08x"
                        " addr=%s", devices[i].mType, devices[i].mAddress.string());
                return INVALID_OPERATION;
            }
        }
    }
    return res;
}
```

在AudioPolicyManager中继续调用到mPolicyMixes.setUidDeviceAffinities(uid, devices)，我们看下

```cpp
status_t AudioPolicyMixCollection::setUidDeviceAffinities(uid_t uid,
        const Vector<AudioDeviceTypeAddr>& devices) {

    for (size_t i = 0; i < size(); i++) {
        const AudioPolicyMix* mix = itemAt(i).get();

        if (!mix->isDeviceAffinityCompatible()) {
            continue;
        }

        if (mix->hasUidRule(true , uid)) {
            return INVALID_OPERATION;
        }
    }

    removeUidDeviceAffinities(uid);

    for (size_t i = 0; i < size(); i++) {
        const AudioPolicyMix *mix = itemAt(i).get();
        if (!mix->isDeviceAffinityCompatible()) {
            continue;
        }

        bool deviceMatch = false;

        for (size_t j = 0; j < devices.size(); j++) {
            if (devices[j].mType == mix->mDeviceType
                    && devices[j].mAddress == mix->mDeviceAddress) {
                deviceMatch = true;
                break;
            }
        }

        if (!deviceMatch && !mix->hasMatchUidRule()) {

            if (!mix->hasUidRule(false , uid)) {

                mix->setExcludeUid(uid);
            }
        }
    }

    return NO_ERROR;
}
```

最终的mix->setExcludeUid(uid)，改变了add了一个crit，我们简单看下这个源码

```cpp
void AudioMix::setExcludeUid(uid_t uid) const {
    AudioMixMatchCriterion crit;
    crit.mRule = RULE_EXCLUDE_UID;
    crit.mValue.mUid = uid;
    mCriteria.add(crit);
}
```

**这样把uid与audiomix就关联到一起了，这个逻辑就像这个单词Exclude，这是一个排除的关联，如果我们把uid关联到zone1中，那么zone2的audiomix会执行setExcludeUid。不是把uid和它对应音区的AudioMIx关联到一起，而是把uid与其对应因音区外的AudioMix关联上，此这块逻辑还需要细细体会理解。**
到此AudioMix的部分也就结束了。

我们上层应用在setZoneIdForUid的时候，会调用到setUidDeviceAffinity，进而最终调用到AudioPolicy下的AudioPolicyMix中，最后把uid与AudioMix绑定到一起，实现路由功能。
到此CarAudio关于源码的逻辑就到这里了，可能有些地方说的不是很清楚，接下来会从一个demo在重新梳理下这部分逻辑。
