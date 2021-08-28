---
link: https://blog.csdn.net/l328873524/article/details/116957494
title: Android R- CarAudioService之registerAudioPolicy动态注册(三)
description: 前言
keywords: Android R- CarAudioService之registerAudioPolicy动态注册(三)
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2021-06-02T15:16:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=37 sentences=69, words=382
---
## 前言

最近又隔了好久没有更新了，实在抱歉，简单总结下之前的分析，前面分析了car_audio_configuration.xml的组成以及CarAudioServic如何解析car_audio_configuration.xml和AudioPolicy的构建。其实在CarAudioService中构建完AudioPolicy后就是registerAudioPolicy过程了，今天我们重点看下这部分的源码。

## 正文

首先简单看下时序图：
![](https://img-blog.csdnimg.cn/20210602221806163.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70)
代码setupDynamicRoutingLocked这里我们也七七八八分析差不多了。剩下的就是registerAudioPolicy了

```java
    private void setupDynamicRoutingLocked() {
        final AudioPolicy.Builder builder = new AudioPolicy.Builder(mContext);
        builder.setLooper(Looper.getMainLooper());
		.......

        builder.setAudioPolicyVolumeCallback(mAudioPolicyVolumeCallback);

        if (sUseCarAudioFocus) {

            mFocusHandler = new CarZonesAudioFocus(mAudioManager,
                    mContext.getPackageManager(),
                    mCarAudioZones,
                    mCarAudioSettings, ENABLE_DELAYED_AUDIO_FOCUS);

            builder.setAudioPolicyFocusListener(mFocusHandler);
            builder.setIsAudioFocusPolicy(true);
        }

        mAudioPolicy = builder.build();
		.......

        int r = mAudioManager.registerAudioPolicy(mAudioPolicy);
        if (r != AudioManager.SUCCESS) {
            throw new RuntimeException("registerAudioPolicy failed " + r);
        }
    }
```

我们继续看下AudioManager中的registerAudioPolicy：

```java
    @SystemApi
    @RequiresPermission(android.Manifest.permission.MODIFY_AUDIO_ROUTING)
    public int registerAudioPolicy(@NonNull AudioPolicy policy) {
        return registerAudioPolicyStatic(policy);
    }
```

函数比较简单，只是简单的一个权限检查，注意这个是一个hide并且system的API，也就是第三方应用是无法调用的，只有定制的系统应用才可使用，继续看下registerAudioPolicyStatic：

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
    }
```

这里简单说下registerAudioPolicy的几个参数：

* policy.getConfig() 这个是在创建AudioPolicy的时候AudioPolicy内部创建的主要处理AudioMix的。
* policy.cb() 即 IAudioPolicyCallback，处理AudioPolicy回调的包括音量以及AudioFocus.

* policy.hasFocusListener() 是否set过setAudioPolicyFocusListener
* policy.isFocusPolicy() 是否sett过setIsAudioFocusPolicy
* policy.isTestFocusPolicy() 是否set过setTestFocusPolicy（默认false）
* policy.isVolumeController()是否set过setAudioPolicyVolumeCallback

到这里AudioManager的部分就结束了。剩下就是AudioService了。我们继续分析AudioService中的registerAudioPolicy
代码很长，摘录核心部分如下：

```java
    public String registerAudioPolicy(AudioPolicyConfig policyConfig, IAudioPolicyCallback pcb,
            boolean hasFocusListener, boolean isFocusPolicy, boolean isTestFocusPolicy,
            boolean isVolumeController, IMediaProjection projection) {
			 ......

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

这里主要就是new一个内部类AudioPolicyProxy，我们继续看下AudioPolicyProxy内部的实现逻辑，代码很长，只有一句主要的核心代码就是

```java
 int status = connectMixes();
```

connectMixes实际就是将我们设置好的AudioPolicy注册下去到native的AudioPolicy中

```java
        @AudioSystem.AudioSystemError int connectMixes() {
            final long identity = Binder.clearCallingIdentity();
            int status = AudioSystem.registerPolicyMixes(mMixes, true);
            Binder.restoreCallingIdentity(identity);
            return status;
        }
```

到此AudioPolicy在java层注册逻辑就结束了，后面就是通过JNI到native的逻辑了。

## 总结

简单总结下这部分逻辑：

1. 首先CarAudioService将构建好的AudioPolicy注册到AudioService中。
2. AudioService中同时创建一个AudioPolicyProxy的内部类，并将注册进来的AudioPolicy放到mAudioPolicies中维护。
3. AudioPolicyProxy在构建的时候会解析AudioPolicy里面的部分参数，比如Volume相关的以及AudioFocus相关的listner并与AudioService中部分模块关联起来。
4. connectMixes将AudioPolicy继续通过AudioSystem注册下去。
5. 注册成功将结果反馈给AudioPolicy。

下一章我们开始分析native层的registerAudioPolicy过程，欢迎大家沟通交流喜欢就关注一波吧
