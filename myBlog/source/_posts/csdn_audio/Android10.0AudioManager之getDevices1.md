---
link: https://blog.csdn.net/l328873524/article/details/105320972
title: Android10.0AudioManager之getDevices（一）
description: 前言
keywords: Android10.0AudioManager之getDevices（一）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-07T13:19:00.000Z
publisher: null
stats: paragraph=75 sentences=126, words=1926
---
我们使用AudioManager最多的Api可能就是申请音频焦点和调节声音音量的了，其实随着Android版本的不断迭代，AudioManager的功能也是不断的完善和增加，那么今天我们就来分析一下AudioManager的getDevices

先上源码Api之getDevices

```java

    public AudioDeviceInfo[] getDevices(int flags) {
        return getDevicesStatic(flags);
    }
```

通过注释我们知道flags可以是GET_DEVICES_OUTPUTS、GET_DEVICES_INPUTS或者GET_DEVICES_ALL，关于AudioDeviceInfo的属性这个我们可参照audio_policy_configuration.xml里的元素

```java
                <devicePort tagName="bus0_media_out" role="sink" type="AUDIO_DEVICE_OUT_BUS"
                        address="bus0_media_out">
                    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
                            samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
                    <gains>
                        <gain name="" mode="AUDIO_GAIN_MODE_JOINT"
                                minValueMB="-3200" maxValueMB="600" defaultValueMB="0" stepValueMB="100"/>
                    </gains>
                </devicePort>

```

主要有samplingRates、channelMasks、format、address、等，我们继续分析

```java
    public static AudioDeviceInfo[] getDevicesStatic(int flags) {
        ArrayList<AudioDevicePort> ports = new ArrayList<AudioDevicePort>();
        int status = AudioManager.listAudioDevicePorts(ports);
        if (status != AudioManager.SUCCESS) {

            return new AudioDeviceInfo[0];
        }

        return infoListFromPortList(ports, flags);
    }
```

这里分了两步，为了方便梳理时序，我们假设是 1 和2。第1步是通过AudioManager.listAudioDevicePorts(ports)去拿设备节点，第2步infoListFromPortList(ports, flags)去构造我们需要的AudioDeviceInfo[]我们先来看listAudioDevicePorts

```java
    public static int listAudioDevicePorts(ArrayList<AudioDevicePort> devices) {
        if (devices == null) {
            return ERROR_BAD_VALUE;
        }
        ArrayList<AudioPort> ports = new ArrayList<AudioPort>();
        int status = updateAudioPortCache(ports, null, null);
        if (status == SUCCESS) {
            filterDevicePorts(ports, devices);
        }
        return status;
    }
```

也是分了两步，假设1.1和1.2，我们还是一点一点分析，先看1.1 updateAudioPortCache

```java
    static int updateAudioPortCache(ArrayList<AudioPort> ports, ArrayList<AudioPatch> patches,
                                    ArrayList<AudioPort> previousPorts) {
        sAudioPortEventHandler.init();
        synchronized (sAudioPortGeneration) {

            if (sAudioPortGeneration == AUDIOPORT_GENERATION_INIT) {

                int[] patchGeneration = new int[1];
                int[] portGeneration = new int[1];
                int status;

                ArrayList<AudioPort> newPorts = new ArrayList<AudioPort>();
                ArrayList<AudioPatch> newPatches = new ArrayList<AudioPatch>();

                do {
                    newPorts.clear();

                    status = AudioSystem.listAudioPorts(newPorts, portGeneration);
                    if (status != SUCCESS) {
                        Log.w(TAG, "updateAudioPortCache: listAudioPorts failed");
                        return status;
                    }
                    newPatches.clear();

                    status = AudioSystem.listAudioPatches(newPatches, patchGeneration);
                    if (status != SUCCESS) {
                        Log.w(TAG, "updateAudioPortCache: listAudioPatches failed");
                        return status;
                    }

                } while (patchGeneration[0] != portGeneration[0]
                        && (ports == null || patches == null));

                if (patchGeneration[0] != portGeneration[0]) {
                    return ERROR;
                }

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
                for (Iterator<AudioPatch> i = newPatches.iterator(); i.hasNext(); ) {
                    AudioPatch newPatch = i.next();
                    boolean hasInvalidPort = false;
                    for (AudioPortConfig portCfg : newPatch.sources()) {
                        if (portCfg == null) {
                            hasInvalidPort = true;
                            break;
                        }
                    }
                    for (AudioPortConfig portCfg : newPatch.sinks()) {
                        if (portCfg == null) {
                            hasInvalidPort = true;
                            break;
                        }
                    }
                    if (hasInvalidPort) {

                        i.remove();
                    }
                }

                sPreviousAudioPortsCached = sAudioPortsCached;
                sAudioPortsCached = newPorts;
                sAudioPatchesCached = newPatches;
                sAudioPortGeneration = portGeneration[0];
            }
            if (ports != null) {
                ports.clear();
                ports.addAll(sAudioPortsCached);
            }
            if (patches != null) {
                patches.clear();
                patches.addAll(sAudioPatchesCached);
            }
            if (previousPorts != null) {
                previousPorts.clear();
                previousPorts.addAll(sPreviousAudioPortsCached);
            }
        }
        return SUCCESS;
    }
```

先看下 1.1.1AudioSystem.listAudioPorts(newPorts, portGeneration)通过AudioSystem直接调到了jni

```cpp
android_media_AudioSystem_listAudioPorts(JNIEnv *env, jobject clazz,
                                         jobject jPorts, jintArray jGeneration)
{
    ALOGV("listAudioPorts");

    if (jPorts == NULL) {
        ALOGE("listAudioPorts NULL AudioPort ArrayList");
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }
    if (!env->IsInstanceOf(jPorts, gArrayListClass)) {
        ALOGE("listAudioPorts not an arraylist");
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }

    if (jGeneration == NULL || env->GetArrayLength(jGeneration) != 1) {
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }

    status_t status;
    unsigned int generation1;
    unsigned int generation;
    unsigned int numPorts;
    jint *nGeneration;
    struct audio_port *nPorts = NULL;
    int attempts = MAX_PORT_GENERATION_SYNC_ATTEMPTS;
    jint jStatus;

    do {
        if (attempts-- < 0) {
            status = TIMED_OUT;
            break;
        }

        numPorts = 0;

        status = AudioSystem::listAudioPorts(AUDIO_PORT_ROLE_NONE,
                                             AUDIO_PORT_TYPE_NONE,
                                                      &numPorts,
                                                      NULL,
                                                      &generation1);
        if (status != NO_ERROR) {
            ALOGE_IF(status != NO_ERROR, "AudioSystem::listAudioPorts error %d", status);
            break;
        }
        if (numPorts == 0) {
            jStatus = (jint)AUDIO_JAVA_SUCCESS;
            goto exit;
        }

        nPorts = (struct audio_port *)realloc(nPorts, numPorts * sizeof(struct audio_port));

        status = AudioSystem::listAudioPorts(AUDIO_PORT_ROLE_NONE,
                                             AUDIO_PORT_TYPE_NONE,
                                                      &numPorts,
                                                      nPorts,
                                                      &generation);
        ALOGV("listAudioPorts AudioSystem::listAudioPorts numPorts %d generation %d generation1 %d",
              numPorts, generation, generation1);
    } while (generation1 != generation && status == NO_ERROR);

    jStatus = nativeToJavaStatus(status);
    if (jStatus != AUDIO_JAVA_SUCCESS) {
        goto exit;
    }

    for (size_t i = 0; i < numPorts; i++) {
        jobject jAudioPort = NULL;
        jStatus = convertAudioPortFromNative(env, &jAudioPort, &nPorts[i]);
        if (jStatus != AUDIO_JAVA_SUCCESS) {
            goto exit;
        }
        env->CallBooleanMethod(jPorts, gArrayListMethods.add, jAudioPort);
        if (jAudioPort != NULL) {
            env->DeleteLocalRef(jAudioPort);
        }
    }

exit:
    nGeneration = env->GetIntArrayElements(jGeneration, NULL);
    if (nGeneration == NULL) {
        jStatus = (jint)AUDIO_JAVA_ERROR;
    } else {
        nGeneration[0] = generation1;
        env->ReleaseIntArrayElements(jGeneration, nGeneration, 0);
    }
    free(nPorts);
    return jStatus;
}
```

通过jni我们看到调用了两次 AudioSystem::listAudioPorts，其实只有第二次才是真正的调用，第一次只是为了遍历audioport的数量以便重新分配内存。我们来具体看下AudioPolicyManager的listAudioPorts过程

```cpp
status_t AudioPolicyManager::listAudioPorts(audio_port_role_t role,
                                            audio_port_type_t type,
                                            unsigned int *num_ports,
                                            struct audio_port *ports,
                                            unsigned int *generation)
{
    if (num_ports == NULL || (*num_ports != 0 && ports == NULL) ||
            generation == NULL) {
        return BAD_VALUE;
    }
    ALOGV("listAudioPorts() role %d type %d num_ports %d ports %p", role, type, *num_ports, ports);
    if (ports == NULL) {
        *num_ports = 0;
    }

    size_t portsWritten = 0;
    size_t portsMax = *num_ports;
    *num_ports = 0;
    if (type == AUDIO_PORT_TYPE_NONE || type == AUDIO_PORT_TYPE_DEVICE) {

        if (role == AUDIO_PORT_ROLE_SINK || role == AUDIO_PORT_ROLE_NONE) {
            for (const auto& dev : mAvailableOutputDevices) {
                if (dev->type() == AUDIO_DEVICE_OUT_STUB) {
                    continue;
                }

                if (portsWritten < portsMax) {
                    dev->toAudioPort(&ports[portsWritten++]);
                }
                (*num_ports)++;
            }
        }
        if (role == AUDIO_PORT_ROLE_SOURCE || role == AUDIO_PORT_ROLE_NONE) {
            for (const auto& dev : mAvailableInputDevices) {
                if (dev->type() == AUDIO_DEVICE_IN_STUB) {
                    continue;
                }

                if (portsWritten < portsMax) {
                    dev->toAudioPort(&ports[portsWritten++]);
                }
                (*num_ports)++;
            }
        }
    }
    if (type == AUDIO_PORT_TYPE_NONE || type == AUDIO_PORT_TYPE_MIX) {
        if (role == AUDIO_PORT_ROLE_SINK || role == AUDIO_PORT_ROLE_NONE) {
            for (size_t i = 0; i < mInputs.size() && portsWritten < portsMax; i++) {
                mInputs[i]->toAudioPort(&ports[portsWritten++]);
            }
            *num_ports += mInputs.size();
        }
        if (role == AUDIO_PORT_ROLE_SOURCE || role == AUDIO_PORT_ROLE_NONE) {
            size_t numOutputs = 0;
            for (size_t i = 0; i < mOutputs.size(); i++) {
                if (!mOutputs[i]->isDuplicated()) {
                    numOutputs++;
                    if (portsWritten < portsMax) {
                        mOutputs[i]->toAudioPort(&ports[portsWritten++]);
                    }
                }
            }
            *num_ports += numOutputs;
        }
    }
    *generation = curAudioPortGeneration();
    ALOGV("listAudioPorts() got %zu ports needed %d", portsWritten, *num_ports);
    return NO_ERROR;
}
```

我们看到，因为第一次传入的*num_ports为0，即portsMax为0.因此不会走dev->toAudioPort只会 (*num_ports)++，所以只有第二次才会真正的toAudioPort，那么都加载了哪些设备？有mAvailableInputDevices和mOutputs以及mAvailableInputDevices和mInputs，其实最终也就是取了我们在audiopolicyManager初始化的时候解析xml的那些attachedDevices 对应的audioport和mixPort对应的audioport取出来了。
我们继续往回看，来分析下1.1.2listAudioPatches，也是先看jni的逻辑，代码有点长

```cpp
android_media_AudioSystem_listAudioPatches(JNIEnv *env, jobject clazz,
                                           jobject jPatches, jintArray jGeneration)
{
    ALOGV("listAudioPatches");
    if (jPatches == NULL) {
        ALOGE("listAudioPatches NULL AudioPatch ArrayList");
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }
    if (!env->IsInstanceOf(jPatches, gArrayListClass)) {
        ALOGE("listAudioPatches not an arraylist");
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }

    if (jGeneration == NULL || env->GetArrayLength(jGeneration) != 1) {
        return (jint)AUDIO_JAVA_BAD_VALUE;
    }

    status_t status;
    unsigned int generation1;
    unsigned int generation;
    unsigned int numPatches;
    jint *nGeneration;
    struct audio_patch *nPatches = NULL;
    jobjectArray jSources = NULL;
    jobject jSource = NULL;
    jobjectArray jSinks = NULL;
    jobject jSink = NULL;
    jobject jPatch = NULL;
    int attempts = MAX_PORT_GENERATION_SYNC_ATTEMPTS;
    jint jStatus;

    do {
        if (attempts-- < 0) {
            status = TIMED_OUT;
            break;
        }

        numPatches = 0;
        status = AudioSystem::listAudioPatches(&numPatches,
                                               NULL,
                                               &generation1);
        if (status != NO_ERROR) {
            ALOGE_IF(status != NO_ERROR, "listAudioPatches AudioSystem::listAudioPatches error %d",
                                      status);
            break;
        }
        if (numPatches == 0) {
            jStatus = (jint)AUDIO_JAVA_SUCCESS;
            goto exit;
        }

        nPatches = (struct audio_patch *)realloc(nPatches, numPatches * sizeof(struct audio_patch));

        status = AudioSystem::listAudioPatches(&numPatches,
                                               nPatches,
                                               &generation);
        ALOGV("listAudioPatches AudioSystem::listAudioPatches numPatches %d generation %d generation1 %d",
              numPatches, generation, generation1);

    } while (generation1 != generation && status == NO_ERROR);

    jStatus = nativeToJavaStatus(status);
    if (jStatus != AUDIO_JAVA_SUCCESS) {
        goto exit;
    }

    for (size_t i = 0; i < numPatches; i++) {
        jobject patchHandle = env->NewObject(gAudioHandleClass, gAudioHandleCstor,
                                                 nPatches[i].id);
        if (patchHandle == NULL) {
            jStatus = AUDIO_JAVA_ERROR;
            goto exit;
        }
        ALOGV("listAudioPatches patch %zu num_sources %d num_sinks %d",
              i, nPatches[i].num_sources, nPatches[i].num_sinks);

        env->SetIntField(patchHandle, gAudioHandleFields.mId, nPatches[i].id);

        jSources = env->NewObjectArray(nPatches[i].num_sources,
                                       gAudioPortConfigClass, NULL);
        if (jSources == NULL) {
            jStatus = AUDIO_JAVA_ERROR;
            goto exit;
        }

        for (size_t j = 0; j < nPatches[i].num_sources; j++) {
            jStatus = convertAudioPortConfigFromNative(env,
                                                      NULL,
                                                      &jSource,
                                                      &nPatches[i].sources[j]);
            if (jStatus != AUDIO_JAVA_SUCCESS) {
                goto exit;
            }
            env->SetObjectArrayElement(jSources, j, jSource);
            env->DeleteLocalRef(jSource);
            jSource = NULL;
            ALOGV("listAudioPatches patch %zu source %zu is a %s handle %d",
                  i, j,
                  nPatches[i].sources[j].type == AUDIO_PORT_TYPE_DEVICE ? "device" : "mix",
                  nPatches[i].sources[j].id);
        }

        jSinks = env->NewObjectArray(nPatches[i].num_sinks,
                                     gAudioPortConfigClass, NULL);
        if (jSinks == NULL) {
            jStatus = AUDIO_JAVA_ERROR;
            goto exit;
        }

        for (size_t j = 0; j < nPatches[i].num_sinks; j++) {
            jStatus = convertAudioPortConfigFromNative(env,
                                                      NULL,
                                                      &jSink,
                                                      &nPatches[i].sinks[j]);

            if (jStatus != AUDIO_JAVA_SUCCESS) {
                goto exit;
            }
            env->SetObjectArrayElement(jSinks, j, jSink);
            env->DeleteLocalRef(jSink);
            jSink = NULL;
            ALOGV("listAudioPatches patch %zu sink %zu is a %s handle %d",
                  i, j,
                  nPatches[i].sinks[j].type == AUDIO_PORT_TYPE_DEVICE ? "device" : "mix",
                  nPatches[i].sinks[j].id);
        }

        jPatch = env->NewObject(gAudioPatchClass, gAudioPatchCstor,
                                       patchHandle, jSources, jSinks);
        env->DeleteLocalRef(jSources);
        jSources = NULL;
        env->DeleteLocalRef(jSinks);
        jSinks = NULL;
        if (jPatch == NULL) {
            jStatus = AUDIO_JAVA_ERROR;
            goto exit;
        }
        env->CallBooleanMethod(jPatches, gArrayListMethods.add, jPatch);
        env->DeleteLocalRef(jPatch);
        jPatch = NULL;
    }

exit:

    nGeneration = env->GetIntArrayElements(jGeneration, NULL);
    if (nGeneration == NULL) {
        jStatus = AUDIO_JAVA_ERROR;
    } else {
        nGeneration[0] = generation1;
        env->ReleaseIntArrayElements(jGeneration, nGeneration, 0);
    }

    if (jSources != NULL) {
        env->DeleteLocalRef(jSources);
    }
    if (jSource != NULL) {
        env->DeleteLocalRef(jSource);
    }
    if (jSinks != NULL) {
        env->DeleteLocalRef(jSinks);
    }
    if (jSink != NULL) {
        env->DeleteLocalRef(jSink);
    }
    if (jPatch != NULL) {
        env->DeleteLocalRef(jPatch);
    }
    free(nPatches);
    return jStatus;
}
```

如果没啥耐心，不看也罢，基本跟toAudioPort逻辑一样，，不罗嗦了，我们这里看下AudioPolicyManager中的

```cpp
status_t AudioPolicyManager::listAudioPatches(unsigned int *num_patches,
                                              struct audio_patch *patches,
                                              unsigned int *generation)
{
    if (generation == NULL) {
        return BAD_VALUE;
    }
    *generation = curAudioPortGeneration();
    return mAudioPatches.listAudioPatches(num_patches, patches);
}
```

最终又调用到了AudioPatch中

```cpp
status_t AudioPatchCollection::listAudioPatches(unsigned int *num_patches,
                                                struct audio_patch *patches) const
{
    if (num_patches == NULL || (*num_patches != 0 && patches == NULL)) {
        return BAD_VALUE;
    }
    ALOGV("listAudioPatches() num_patches %d patches %p available patches %zu",
          *num_patches, patches, size());
    if (patches == NULL) {
        *num_patches = 0;
    }

    size_t patchesWritten = 0;
    size_t patchesMax = *num_patches;
    *num_patches = 0;
    for (size_t patchIndex = 0; patchIndex < size(); patchIndex++) {

        const sp<AudioPatch> patch = valueAt(patchIndex);
        bool skip = false;
        for (size_t srcIndex = 0; srcIndex < patch->mPatch.num_sources && !skip; srcIndex++) {
            if (patch->mPatch.sources[srcIndex].type == AUDIO_PORT_TYPE_DEVICE &&
                    patch->mPatch.sources[srcIndex].ext.device.type == AUDIO_DEVICE_IN_STUB) {
                skip = true;
            }
        }
        for (size_t sinkIndex = 0; sinkIndex < patch->mPatch.num_sinks && !skip; sinkIndex++) {
            if (patch->mPatch.sinks[sinkIndex].type == AUDIO_PORT_TYPE_DEVICE &&
                    patch->mPatch.sinks[sinkIndex].ext.device.type == AUDIO_DEVICE_OUT_STUB) {
                skip = true;
            }
        }
        if (skip) {
            continue;
        }
        if (patchesWritten < patchesMax) {
            patches[patchesWritten] = patch->mPatch;
            patches[patchesWritten++].id = patch->mHandle;
        }
        (*num_patches)++;
        ALOGV("listAudioPatches() patch %zu num_sources %d num_sinks %d",
              patchIndex, patch->mPatch.num_sources, patch->mPatch.num_sinks);
    }

    ALOGV("listAudioPatches() got %zu patches needed %d", patchesWritten, *num_patches);
    return NO_ERROR;
}
```

和audioport逻辑一样，这里不多说了。

代码有点多，简单总结下，从AudioManager的getDevices开始通过AudioSystem调到android_media_AudioSystem(jni)最终从AudioPolicyManager中拿到我们要的audioport和audiopatch。
下章我们继续向回分析，拿到数据后又是如何最终通过AudioManager返给应用的。
（以上分析如有错误，欢迎指正沟通~感激不尽）
