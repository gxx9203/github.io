---
link: https://blog.csdn.net/l328873524/article/details/105942505
title: Android10.0CarAudioZone（四）
description: 前言上几篇讲了CarAudioZone相关的volume、audiofocus以及device，我们也知道在CarAudioService的初始化过程中，最后通过mAudioManager.registerAudioPolicy(mAudioPolicy)将AudioPolicy注册下去的，那么今天我们继续分析AudioPolicy的register过程。正文...
keywords: Android10.0CarAudioZone（四）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-05-08T13:32:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=99 sentences=192, words=1840
---
上几篇讲了CarAudioZone相关的volume、audiofocus以及device，我们也知道在CarAudioService的初始化过程中，最后通过mAudioManager.registerAudioPolicy(mAudioPolicy)将AudioPolicy注册下去的，那么今天我们继续分析AudioPolicy的register过程。

首先看下AudioManager的registerAudioPolicy

```java
    public int registerAudioPolicy(@NonNull AudioPolicy policy) {
        return registerAudioPolicyStatic(policy);
    }
```

继续看

```java
    static int registerAudioPolicyStatic(@NonNull AudioPolicy policy) {
        if (policy == null) {
            throw new IllegalArgumentException("Illegal null AudioPolicy argument");
        }
        final IAudioService service = getService();
        try {

            MediaProjection projection = policy.getMediaProjection();

            String regId = service.registerAudioPolicy(policy.getConfig(), policy.cb(),
                    policy.hasFocusListener(), policy.isFocusPolicy(), policy.isTestFocusPolicy(),
                    policy.isVolumeController(),
                    projection == null ? null : projection.getProjection());
            if (regId == null) {
                return ERROR;
            } else {
                policy.setRegistration(regId);
            }

        } catch (RemoteException e) {
            throw e.rethrowFromSystemServer();
        }
        return SUCCESS;

```

最终调到了AudioService的registerAudioPolicy

```java
    public String registerAudioPolicy(AudioPolicyConfig policyConfig, IAudioPolicyCallback pcb,
            boolean hasFocusListener, boolean isFocusPolicy, boolean isTestFocusPolicy,
            boolean isVolumeController, IMediaProjection projection) {
        AudioSystem.setDynamicPolicyCallback(mDynPolicyCallback);

        if (!isPolicyRegisterAllowed(policyConfig,
                                     isFocusPolicy || isTestFocusPolicy || hasFocusListener,
                                     isVolumeController,
                                     projection)) {
            Slog.w(TAG, "Permission denied to register audio policy for pid "
                    + Binder.getCallingPid() + " / uid " + Binder.getCallingUid()
                    + ", need MODIFY_AUDIO_ROUTING or MediaProjection that can project audio");
            return null;
        }

        mDynPolicyLogger.log((new AudioEventLogger.StringEvent("registerAudioPolicy for "
                + pcb.asBinder() + " with config:" + policyConfig)).printLog(TAG));

        String regId = null;
        synchronized (mAudioPolicies) {

            if (mAudioPolicies.containsKey(pcb.asBinder())) {
                Slog.e(TAG, "Cannot re-register policy");
                return null;
            }
            try {

                AudioPolicyProxy app = new AudioPolicyProxy(policyConfig, pcb, hasFocusListener,
                        isFocusPolicy, isTestFocusPolicy, isVolumeController, projection);
                pcb.asBinder().linkToDeath(app, 0);
                regId = app.getRegistrationId();

                mAudioPolicies.put(pcb.asBinder(), app);
            } catch (RemoteException e) {

                Slog.w(TAG, "Audio policy registration failed, could not link to " + pcb +
                        " binder death", e);
                return null;
            } catch (IllegalStateException e) {
                Slog.w(TAG, "Audio policy registration failed for binder " + pcb, e);
                return null;
            }
        }
        return regId;
    }
```

我们先看下这几个传入的参数，policyConfig是我们构建AudioPolicy的时候new的，pcb是AudioPolicy中初始化的，用于处理音频焦点的回调， 即 private final IAudioPolicyCallback mPolicyCb = new IAudioPolicyCallback.Stub()，hasFocusListener（即CarZonesAudioFocus）和isFocusPolicy都是true，isTestFocusPolicy是false，isVolumeController是ture（在CarAudioService中创建的 private final AudioPolicy.AudioPolicyVolumeCallback mAudioPolicyVolumeCallback）, projection是null，首先执行了 AudioSystem.setDynamicPolicyCallback(mDynPolicyCallback)，通过jni最终

```java
 void AudioSystem::setDynPolicyCallback(dynamic_policy_callback cb)
{
    Mutex::Autolock _l(gLock);
    gDynPolicyCallback = cb;
}
```

调用到native的AudioSystem中。我们在看到这个参数记得是这里传下去的。继续看register的过程，下来是isPolicyRegisterAllowed的判断

```java
   private boolean isPolicyRegisterAllowed(AudioPolicyConfig policyConfig,
                                            boolean hasFocusAccess,
                                            boolean isVolumeController,
                                            IMediaProjection projection) {

        boolean requireValidProjection = false;
        boolean requireCaptureAudioOrMediaOutputPerm = false;
        boolean requireModifyRouting = false;

        if (hasFocusAccess || isVolumeController) {

            requireModifyRouting |= true;
        } else if (policyConfig.getMixes().isEmpty()) {

            requireModifyRouting |= true;
        }

        for (AudioMix mix : policyConfig.getMixes()) {

            if (mix.getRule().allowPrivilegedPlaybackCapture()) {

                requireCaptureAudioOrMediaOutputPerm |= true;

                String error = mix.canBeUsedForPrivilegedCapture(mix.getFormat());
                if (error != null) {
                    Log.e(TAG, error);
                    return false;
                }
            }

            if (mix.getRouteFlags() == mix.ROUTE_FLAG_LOOP_BACK_RENDER && projection != null) {
                requireValidProjection |= true;
            } else {
                requireModifyRouting |= true;
            }
        }

        if (requireCaptureAudioOrMediaOutputPerm
                && !callerHasPermission(android.Manifest.permission.CAPTURE_MEDIA_OUTPUT)
                && !callerHasPermission(android.Manifest.permission.CAPTURE_AUDIO_OUTPUT)) {
            Log.e(TAG, "Privileged audio capture requires CAPTURE_MEDIA_OUTPUT or "
                      + "CAPTURE_AUDIO_OUTPUT system permission");
            return false;
        }

        if (requireValidProjection && !canProjectAudio(projection)) {
            return false;
        }

        if (requireModifyRouting
                && !callerHasPermission(android.Manifest.permission.MODIFY_AUDIO_ROUTING)) {
            Log.e(TAG, "Can not capture audio without MODIFY_AUDIO_ROUTING");
            return false;
        }

        return true;
    }

```

代码很长，但里面的if基本都是不满足的，最终return true，继续往下看就是new AudioPolicyProxy了。我们看下AudioPolicyProxy的创建过程。

```java
        AudioPolicyProxy(AudioPolicyConfig config, IAudioPolicyCallback token,
                boolean hasFocusListener, boolean isFocusPolicy, boolean isTestFocusPolicy,
                boolean isVolumeController, IMediaProjection projection) {
            super(config);
            setRegistration(new String(config.hashCode() + ":ap:" + mAudioPolicyCounter++));
            mPolicyCallback = token;
            mHasFocusListener = hasFocusListener;
            mIsVolumeController = isVolumeController;
            mProjection = projection;

            if (mHasFocusListener) {
                mMediaFocusControl.addFocusFollower(mPolicyCallback);

                if (isFocusPolicy) {
                    mIsFocusPolicy = true;
                    mIsTestFocusPolicy = isTestFocusPolicy;
                    mMediaFocusControl.setFocusPolicy(mPolicyCallback, mIsTestFocusPolicy);
                }
            }
            if (mIsVolumeController) {
                setExtVolumeController(mPolicyCallback);
            }

            if (mProjection != null) {
                mProjectionCallback = new UnregisterOnStopCallback();
                try {
                    mProjection.registerCallback(mProjectionCallback);
                } catch (RemoteException e) {
                    release();
                    throw new IllegalStateException("MediaProjection callback registration failed, "
                            + "could not link to " + projection + " binder death", e);
                }
            }

            int status = connectMixes();
            if (status != AudioSystem.SUCCESS) {
                release();
                throw new IllegalStateException("Could not connect mix, error: " + status);
            }
        }
```

他是AudioService的一个内部类继承自AudioPolicyConfig。这部分很重要，我们拆分一点一点来看， 首先setRegistration(new String(config.hashCode() + ":ap:" + mAudioPolicyCounter++))

```java
    protected void setRegistration(String regId) {

        final boolean currentRegNull = (mRegistrationId == null) || mRegistrationId.isEmpty();

        final boolean newRegNull = (regId == null) || regId.isEmpty();
        if (!currentRegNull && !newRegNull && !mRegistrationId.equals(regId)) {
            Log.e(TAG, "Invalid registration transition from " + mRegistrationId + " to " + regId);
            return;
        }

        mRegistrationId = regId == null ? "" : regId;
        for (AudioMix mix : mMixes) {
            setMixRegistration(mix);
        }
    }
```

这个是父类AudioPolicyConfig中的方法，通过源码了解设置了一个mRegistrationId 后遍历AudioMix执行setMixRegistration，我们继续看看下setMixRegistration(mix)

```java
    private void setMixRegistration(@NonNull final AudioMix mix) {

        if (!mRegistrationId.isEmpty()) {
            if ((mix.getRouteFlags() & AudioMix.ROUTE_FLAG_LOOP_BACK) ==
                    AudioMix.ROUTE_FLAG_LOOP_BACK) {
                mix.setRegistration(mRegistrationId + "mix" + mixTypeId(mix.getMixType()) + ":"
                        + mMixCounter);

            } else if ((mix.getRouteFlags() & AudioMix.ROUTE_FLAG_RENDER) ==
                    AudioMix.ROUTE_FLAG_RENDER) {

                mix.setRegistration(mix.mDeviceAddress);
            }
        } else {
            mix.setRegistration("");
        }
        mMixCounter++;
    }
```

通过代码了解这里又调到了 mix.setRegistration(mix.mDeviceAddress)，我们在看下AudioMIx中的逻辑

```java
    void setRegistration(String regId) {
        mDeviceAddress = regId;
    }
```

这个regId也就是我们传下来的mix.mDeviceAddress，是我我们构建AudioMix时setDevice传入的device的info的address，关于构建AudioMix的过程我们可以参照[Android10.0CarAudioZone（三）](https://blog.csdn.net/l328873524/article/details/105924894)，好了回到AudioPolicyProxy中急需往下看，接下来是 mMediaFocusControl.addFocusFollower(mPolicyCallback)，我们看下MediaFocusControl

```java
    private ArrayList<IAudioPolicyCallback> mFocusFollowers = new ArrayList<IAudioPolicyCallback>();

    void addFocusFollower(IAudioPolicyCallback ff) {
        if (ff == null) {
            return;
        }
        synchronized(mAudioFocusLock) {
            boolean found = false;

            for (IAudioPolicyCallback pcb : mFocusFollowers) {
                if (pcb.asBinder().equals(ff.asBinder())) {
                    found = true;
                    break;
                }
            }
            if (found) {
                return;
            } else {
                mFocusFollowers.add(ff);

                notifyExtPolicyCurrentFocusAsync(ff);
            }
        }
    }
```

这里有个很重要的逻辑notifyExtPolicyCurrentFocusAsync(ff)

```java
    void notifyExtPolicyCurrentFocusAsync(IAudioPolicyCallback pcb) {
        final IAudioPolicyCallback pcb2 = pcb;
        final Thread thread = new Thread() {
            @Override
            public void run() {
                synchronized(mAudioFocusLock) {
                    if (mFocusStack.isEmpty()) {
                        return;
                    }
                    try {
                        pcb2.notifyAudioFocusGrant(mFocusStack.peek().toAudioFocusInfo(),

                                AudioManager.AUDIOFOCUS_REQUEST_GRANTED);
                    } catch (RemoteException e) {
                        Log.e(TAG, "Can't call notifyAudioFocusGrant() on IAudioPolicyCallback "
                                + pcb2.asBinder(), e);
                    }
                }
            }
        };
        thread.start();
    }
```

**如果当前栈里的AudioFocus不为null，也就是有人在我们registerAudioPolicy前requestAudioFocus了。那么我们要把这个AudioFocus拿出来给到外部的音频焦点策略去处理。这里是给到了CarZonesAudioFocus中去处理音频焦点的优先级**，具体处理过程，等我们后面通过demo来说明，这里先不说了。接下来又调用了 mMediaFocusControl.setFocusPolicy(mPolicyCallback, mIsTestFocusPolicy)

```java
    void setFocusPolicy(IAudioPolicyCallback policy, boolean isTestFocusPolicy) {
        if (policy == null) {
            return;
        }
        synchronized (mAudioFocusLock) {

            if (isTestFocusPolicy) {
                mPreviousFocusPolicy = mFocusPolicy;
            }
            mFocusPolicy = policy;
        }
    }
```

这里赋值了mFocusPolicy 。通过这个我们也看出了一点AudioPolicy的setAudioPolicyFocusListener(mFocusHandler)和setIsAudioFocusPolicy(true)，这俩方法是配套使用的。MediaFocusControl的部分就结束了，回到AudioService的new AudioPolicyProxy中继续，setExtVolumeController(mPolicyCallback)

```java
    private void setExtVolumeController(IAudioPolicyCallback apc) {

        if (!mContext.getResources().getBoolean(
                com.android.internal.R.bool.config_handleVolumeKeysInWindowManager)) {
            Log.e(TAG, "Cannot set external volume controller: device not set for volume keys" +
                    " handled in PhoneWindowManager");
            return;
        }
        synchronized (mExtVolumeControllerLock) {
            if (mExtVolumeController != null && !mExtVolumeController.asBinder().pingBinder()) {
                Log.e(TAG, "Cannot set external volume controller: existing controller");
            }
            mExtVolumeController = apc;
        }
    }
```

这部分主要是apc赋值给了mExtVolumeController，也就是把AudioPolicy中的mPolicyCb赋值给了mExtVolumeController。回到new AudioPolicyProxy中最后一步connectMixes()

```java
        int connectMixes() {
            final long identity = Binder.clearCallingIdentity();
            int status = AudioSystem.registerPolicyMixes(mMixes, true);
            Binder.restoreCallingIdentity(identity);
            return status;
        }
```

我们知道一般调到AudioSystem的基本都是要通过jni向下调用了，这里也一样，最终在AudioSystem的native中调到了AudioPolicyService的registerPolicyMixes

```cpp
status_t AudioPolicyService::registerPolicyMixes(const Vector<AudioMix>& mixes, bool registration)
{
    Mutex::Autolock _l(mLock);

    bool needModifyAudioRouting = std::any_of(mixes.begin(), mixes.end(), [](auto& mix) {
            return !is_mix_loopback_render(mix.mRouteFlags); });
    if (needModifyAudioRouting && !modifyAudioRoutingAllowed()) {
        return PERMISSION_DENIED;
    }

    bool needCaptureMediaOutput = std::any_of(mixes.begin(), mixes.end(), [](auto& mix) {
            return mix.mAllowPrivilegedPlaybackCapture; });
    const uid_t callingUid = IPCThreadState::self()->getCallingUid();
    const pid_t callingPid = IPCThreadState::self()->getCallingPid();
    if (needCaptureMediaOutput && !captureMediaOutputAllowed(callingPid, callingUid)) {
        return PERMISSION_DENIED;
    }

    if (mAudioPolicyManager == NULL) {
        return NO_INIT;
    }
    AutoCallerClear acc;

    if (registration) {
        return mAudioPolicyManager->registerPolicyMixes(mixes);
    } else {
        return mAudioPolicyManager->unregisterPolicyMixes(mixes);
    }
}
```

这里继续调用到了AudioPolicyManager的registerPolicyMixes

```cpp
status_t AudioPolicyManager::registerPolicyMixes(const Vector<AudioMix>& mixes)
{
    ALOGV("registerPolicyMixes() %zu mix(es)", mixes.size());
    status_t res = NO_ERROR;

    sp<HwModule> rSubmixModule;

    for (size_t i = 0; i < mixes.size(); i++) {
        AudioMix mix = mixes[i];

        if (is_mix_loopback_render(mix.mRouteFlags) && mix.mMixType != MIX_TYPE_PLAYERS) {
            ALOGE("Unsupported Policy Mix %zu of %zu: "
                  "Only capture of playback is allowed in LOOP_BACK & RENDER mode",
                   i, mixes.size());
            res = INVALID_OPERATION;
            break;
        }

        if ((mix.mRouteFlags & MIX_ROUTE_FLAG_LOOP_BACK) == MIX_ROUTE_FLAG_LOOP_BACK) {
            ALOGV("registerPolicyMixes() mix %zu of %zu is LOOP_BACK %d", i, mixes.size(),
                  mix.mRouteFlags);
            if (rSubmixModule == 0) {
                rSubmixModule = mHwModules.getModuleFromName(
                        AUDIO_HARDWARE_MODULE_ID_REMOTE_SUBMIX);
                if (rSubmixModule == 0) {
                    ALOGE("Unable to find audio module for submix, aborting mix %zu registration",
                            i);
                    res = INVALID_OPERATION;
                    break;
                }
            }

            String8 address = mix.mDeviceAddress;
            audio_devices_t deviceTypeToMakeAvailable;

            if (mix.mMixType == MIX_TYPE_PLAYERS) {
                mix.mDeviceType = AUDIO_DEVICE_OUT_REMOTE_SUBMIX;
                deviceTypeToMakeAvailable = AUDIO_DEVICE_IN_REMOTE_SUBMIX;
            } else {
                mix.mDeviceType = AUDIO_DEVICE_IN_REMOTE_SUBMIX;
                deviceTypeToMakeAvailable = AUDIO_DEVICE_OUT_REMOTE_SUBMIX;
            }

            if (mPolicyMixes.registerMix(mix, 0 ) != NO_ERROR) {
                ALOGE("Error registering mix %zu for address %s", i, address.string());
                res = INVALID_OPERATION;

                break;
            }
            audio_config_t outputConfig = mix.mFormat;
            audio_config_t inputConfig = mix.mFormat;

            outputConfig.channel_mask = AUDIO_CHANNEL_OUT_STEREO;
            inputConfig.channel_mask = AUDIO_CHANNEL_IN_STEREO;
            rSubmixModule->addOutputProfile(address, &outputConfig,
                    AUDIO_DEVICE_OUT_REMOTE_SUBMIX, address);
            rSubmixModule->addInputProfile(address, &inputConfig,
                    AUDIO_DEVICE_IN_REMOTE_SUBMIX, address);

            if ((res = setDeviceConnectionStateInt(deviceTypeToMakeAvailable,
                    AUDIO_POLICY_DEVICE_STATE_AVAILABLE,
                    address.string(), "remote-submix", AUDIO_FORMAT_DEFAULT)) != NO_ERROR) {
                ALOGE("Failed to set remote submix device available, type %u, address %s",
                        mix.mDeviceType, address.string());
                break;
            }

        } else if ((mix.mRouteFlags & MIX_ROUTE_FLAG_RENDER) == MIX_ROUTE_FLAG_RENDER) {
            String8 address = mix.mDeviceAddress;
            audio_devices_t type = mix.mDeviceType;
            ALOGV(" registerPolicyMixes() mix %zu of %zu is RENDER, dev=0x%X addr=%s",
                    i, mixes.size(), type, address.string());

            sp<DeviceDescriptor> device = mHwModules.getDeviceDescriptor(
                    mix.mDeviceType, mix.mDeviceAddress,
                    String8(), AUDIO_FORMAT_DEFAULT);
            if (device == nullptr) {
                res = INVALID_OPERATION;
                break;
            }

            bool foundOutput = false;
            for (size_t j = 0 ; j < mOutputs.size() ; j++) {
                sp<SwAudioOutputDescriptor> desc = mOutputs.valueAt(j);

                if (desc->supportedDevices().contains(device)) {

                    if (mPolicyMixes.registerMix(mix, desc) != NO_ERROR) {
                        ALOGE("Could not register mix RENDER,  dev=0x%X addr=%s", type,
                              address.string());
                        res = INVALID_OPERATION;
                    } else {
                        foundOutput = true;
                    }
                    break;
                }
            }

            if (res != NO_ERROR) {
                ALOGE(" Error registering mix %zu for device 0x%X addr %s",
                        i, type, address.string());
                res = INVALID_OPERATION;
                break;
            } else if (!foundOutput) {
                ALOGE(" Output not found for mix %zu for device 0x%X addr %s",
                        i, type, address.string());
                res = INVALID_OPERATION;
                break;
            }
        }
    }
    if (res != NO_ERROR) {
        unregisterPolicyMixes(mixes);
    }
    return res;
}
```

我们看到主要是registerMix(mix, desc)，接下来再来AudioPolicyMix.cpp中看下

```cpp
status_t AudioPolicyMixCollection::registerMix(AudioMix mix, sp<SwAudioOutputDescriptor> desc)
{

    for (size_t i = 0; i < size(); i++) {
        const sp<AudioPolicyMix>& registeredMix = itemAt(i);
        if (mix.mDeviceType == registeredMix->mDeviceType
                && mix.mDeviceAddress.compare(registeredMix->mDeviceAddress) == 0) {
            ALOGE("registerMix(): mix already registered for dev=0x%x addr=%s",
                    mix.mDeviceType, mix.mDeviceAddress.string());
            return BAD_VALUE;
        }
    }
    创建AudioPolicyMix并add到mPolicyMixes中
    sp<AudioPolicyMix> policyMix = new AudioPolicyMix(mix);
    add(policyMix);
    ALOGD("registerMix(): adding mix for dev=0x%x addr=%s",
            policyMix->mDeviceType, policyMix->mDeviceAddress.string());

    if (desc != 0) {
        desc->mPolicyMix = policyMix;
        policyMix->setOutput(desc);
    }
    return NO_ERROR;
}
```

到此注册就结束了，总结一下，registerAudioPolicy主要有这么几个作用
**1.可以将按键调节音量的方法通过AudioPolicy拿到外面我们自定义的模块处理<br>2.可以将AudioFocus的优先级处理通过AudioPolicy拿到外面我们自定义的模块处理<br>3.将AuiioMix注册到AudioPolicyManager下，这样路由策略由原来的根据stream选device，然后根据device选output的方式变更为通过usage直接选output，这个更适合Car上的AUDIO_DEVICE_OUT_BUS**
下一篇我们再说下关于uid在CarAudioZone中的作用
以上欢迎大家交流沟通~
