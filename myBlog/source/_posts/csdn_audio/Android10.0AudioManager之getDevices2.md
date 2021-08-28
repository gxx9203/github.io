---
link: https://blog.csdn.net/l328873524/article/details/105463377
title: Android10.0AudioManager之getDevices（二）
description: 前言Android10.0AudioManager之getDevices（一）我们分析了获取Audioport以及AudioPatch的过程，今天继续正文
keywords: Android10.0AudioManager之getDevices（二）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-13T17:18:00.000Z
publisher: null
stats: paragraph=27 sentences=64, words=520
---
通过AudioPolicyManager我们拿到了AudioPort和AudioPatch，那么回到AudioManager的updateAudioPortCache的 1.1.3

```java
                for (int i = 0; i < newPatches.size(); i++) {
                    for (int j = 0; j < newPatches.get(i).sources().length; j++) {
                        AudioPortConfig portCfg = updatePortConfig(newPatches.get(i).sources()[j],
                                                                   newPorts);
                        newPatches.get(i).sources()[j] = portCfg;
                    }
                    for (int j = 0; j < newPatches.get(i).sinks().length; j++) {
                        AudioPortConfig portCfg = updatePortConfig(newPatches.get(i).sinks()[j],
                                                                   newPorts);
                        newPatches.get(i).sinks()[j] = portCfg;
                    }
                }
```

我们从代码看这部分逻辑是重新赋值newPatches.get(i).sources()[j]和newPatches.get(i).sinks()[j]，那么source和sink是什么呢？
我们在分析[Android10.0audio_policy_configuration.xml解析](https://blog.csdn.net/l328873524/article/details/105374196)的时候，我们分析过mSupportedDevices，它就是这里的sink，它的类型是，DeviceDescriptor : public AudioPort, public AudioPortConfig。我们从继承关系上看即继承了AudioPort又继承了AudioPortConfig。而source是SwAudioOutputDescriptor，也是继承了AudioPortConfig。这部分逻辑可参照AudioPolicyManager的initialize()中的setOutputDevices

```cpp
uint32_t AudioPolicyManager::setOutputDevices(const sp<SwAudioOutputDescriptor>& outputDesc,
                                              const DeviceVector &devices,
                                              bool force,
                                              int delayMs,
                                              audio_patch_handle_t *patchHandle,
                                              bool requiresMuteCheck)
{
    ALOGV("%s device %s delayMs %d", __func__, devices.toString().c_str(), delayMs);
    uint32_t muteWaitMs;

    if (outputDesc->isDuplicated()) {
        muteWaitMs = setOutputDevices(outputDesc->subOutput1(), devices, force, delayMs,
                nullptr , requiresMuteCheck);
        muteWaitMs += setOutputDevices(outputDesc->subOutput2(), devices, force, delayMs,
                nullptr , requiresMuteCheck);
        return muteWaitMs;
    }

    DeviceVector filteredDevices = outputDesc->filterSupportedDevices(devices);
    DeviceVector prevDevices = outputDesc->devices();

    if (!devices.isEmpty() && filteredDevices.isEmpty() &&
            !mAvailableOutputDevices.filter(prevDevices).empty()) {
        ALOGV("%s: unsupported device %s for output", __func__, devices.toString().c_str());
        return 0;
    }

    ALOGV("setOutputDevices() prevDevice %s", prevDevices.toString().c_str());

    if (!filteredDevices.isEmpty()) {
        outputDesc->setDevices(filteredDevices);
    }

    if (requiresMuteCheck) {
        muteWaitMs = checkDeviceMuteStrategies(outputDesc, prevDevices, delayMs);
    } else {
        ALOGV("%s: suppressing checkDeviceMuteStrategies", __func__);
        muteWaitMs = 0;
    }

    if ((filteredDevices.isEmpty() || filteredDevices == prevDevices) &&
            !force && outputDesc->getPatchHandle() != 0) {
        ALOGV("%s setting same device %s or null device, force=%d, patch handle=%d", __func__,
              filteredDevices.toString().c_str(), force, outputDesc->getPatchHandle());
        return muteWaitMs;
    }

    ALOGV("%s changing device to %s", __func__, filteredDevices.toString().c_str());

    if (filteredDevices.isEmpty()) {
        resetOutputDevice(outputDesc, delayMs, NULL);
    } else {
        PatchBuilder patchBuilder;
        patchBuilder.addSource(outputDesc);
        ALOG_ASSERT(filteredDevices.size()  AUDIO_PATCH_PORTS_MAX, "Too many sink ports");
        for (const auto &filteredDevice : filteredDevices) {
            patchBuilder.addSource(filteredDevice);
        }

        installPatch(__func__, patchHandle, outputDesc.get(), patchBuilder.patch(), delayMs);
    }

    applyStreamVolumes(outputDesc, filteredDevices.types(), delayMs);

    return muteWaitMs;
}
```

其中patchBuilder构建的时候，addSource与addSource传入的便是SwAudioOutputDescriptor和outputDesc->filterSupportedDevices(devices)
这块就不多说了，继续看

```java
            if (ports != null) {
                ports.clear();
                ports.addAll(sAudioPortsCached);
            }
            if (patches != null) {
                patches.clear();
                patches.addAll(sAudioPatchesCached);
            }
```

由于我们传入的patches为null这里只操作ports，到此java层就通过jni在AudioPolicyManager中拿到了AudioPort，并在java层重新封装了。我们继续filterDevicePorts(ports, devices);也就是上文说的1.2，这里ports是我们从native层获取的，devices是我们要最终拿到的

```java
    private static void filterDevicePorts(ArrayList<AudioPort> ports,
                                          ArrayList<AudioDevicePort> devices) {
        devices.clear();
        for (int i = 0; i < ports.size(); i++) {
            if (ports.get(i) instanceof AudioDevicePort) {
                devices.add((AudioDevicePort)ports.get(i));
            }
        }
    }
```

代码不是很复杂，只是从AudioPort中过滤出AudioDevicePort，也就是过滤出type为AUDIO_PORT_TYPE_DEVICE的。
回到最后一步infoListFromPortList(ports, flags)

```java
   private static AudioDeviceInfo[]
        infoListFromPortList(ArrayList<AudioDevicePort> ports, int flags) {

        int numRecs = 0;
        for (AudioDevicePort port : ports) {
            if (checkTypes(port) && checkFlags(port, flags)) {
                numRecs++;
            }
        }

        AudioDeviceInfo[] deviceList = new AudioDeviceInfo[numRecs];
        int slot = 0;
        for (AudioDevicePort port : ports) {
            if (checkTypes(port) && checkFlags(port, flags)) {
                deviceList[slot++] = new AudioDeviceInfo(port);
            }
        }

        return deviceList;
    }
```

第一次过滤拿到数量，因为我们知道AudioDevicePort 分output和input，所以这里先根据flag过滤出数量，然后我们再组装我们要的AudioDeviceInfo，最终返回AudioDeviceInfo的lists。

到此，我们AudioManager的getDevices就分析完成了，从AudioManager经过AudioSystem到jni最终再AudioPolicyManager中拿到我们要的AudioPort和AudioPatch，然后再AudioManager根据flag中过滤组装成我们需要的AudioDeviceInfo的list。
（以上，如有问题，欢迎大家指正交流）
