---
link: https://blog.csdn.net/l328873524/article/details/105211554
title: Android10.0AudioFocus之源码分析（二）
description: 前言上一篇我们简单说了AudioFocus如何使用，那么在从源码角度看一下AudioFocus的实现原理呢正文 public int requestAudioFocus(@NonNull AudioFocusRequest focusRequest) {        return requestAudioFocus(focusRequest, null /* no AudioPolicy...
keywords: Android10.0AudioFocus之源码分析（二）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-03-31T17:23:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=66 sentences=146, words=1076
---
上一篇我们简单说了AudioFocus如何使用，那么今天就从源码角度看一下AudioFocus的实现原理。

先说下requestAudioFocus，源码如下：

```java
 public int requestAudioFocus(@NonNull AudioFocusRequest focusRequest) {
        return requestAudioFocus(focusRequest, null );
    }
```

对外的api也是比较简单，这里说下这两个参数，第一个参数，最早传入的是streamtype，到8.0才改用AudioFocusRequest，随着功能的越来越丰富，谷歌特意封装了一个类来处理申请音源的信息，第二个参数 AudioPolicy，这里传的null，从字面理解audio策略，它是一个SystemApi，也就是一般应用是无法使用的，但它主要是允许我们把一些焦点的优先级的处理通过AudioPolicy拿到外部来处理而不是用Android自带的处理逻辑，是不是听着就有点小激动。
先继续分析

```java
    public int requestAudioFocus(@NonNull AudioFocusRequest afr, @Nullable AudioPolicy ap) {
        if (afr == null) {
            throw new NullPointerException("Illegal null AudioFocusRequest");
        }

        if (afr.locksFocus() && ap == null) {
            throw new IllegalArgumentException(
                    "Illegal null audio policy when locking audio focus");
        }

        registerAudioFocusRequest(afr);
        final IAudioService service = getService();
        final int status;
        int sdk;
        try {
            sdk = getContext().getApplicationInfo().targetSdkVersion;
        } catch (NullPointerException e) {

            sdk = Build.VERSION.SDK_INT;
        }

        final String clientId = getIdForAudioFocusListener(afr.getOnAudioFocusChangeListener());
        final BlockingFocusResultReceiver focusReceiver;
        synchronized (mFocusRequestsLock) {
            try {

                status = service.requestAudioFocus(afr.getAudioAttributes(),
                        afr.getFocusGain(), mICallBack,
                        mAudioFocusDispatcher,
                        clientId,
                        getContext().getOpPackageName() , afr.getFlags(),
                        ap != null ? ap.cb() : null,
                        sdk);
            } catch (RemoteException e) {
                throw e.rethrowFromSystemServer();
            }

            if (status != AudioManager.AUDIOFOCUS_REQUEST_WAITING_FOR_EXT_POLICY) {

                return status;
            }

            if (mFocusRequestsAwaitingResult == null) {
                mFocusRequestsAwaitingResult =
                        new HashMap<String, BlockingFocusResultReceiver>(1);
            }

            focusReceiver = new BlockingFocusResultReceiver(clientId);
            mFocusRequestsAwaitingResult.put(clientId, focusReceiver);
        }

        focusReceiver.waitForResult(EXT_FOCUS_POLICY_TIMEOUT_MS);
        if (DEBUG && !focusReceiver.receivedResult()) {
            Log.e(TAG, "requestAudio response from ext policy timed out, denying request");
        }
        synchronized (mFocusRequestsLock) {
            mFocusRequestsAwaitingResult.remove(clientId);
        }

        return focusReceiver.requestResult();
    }
```

以上代码逻辑比较长，简单说下几个步骤
（1）参数的校验
（2）调用AudioService的requestAudioFocus
（3）判断是否有外部的audiopolicy，如果没有直接返回申请结果，如果有则等外外部音频焦点处理结果
这里在顺便说下 registerAudioFocusRequest(afr)

```java
    public void registerAudioFocusRequest(@NonNull AudioFocusRequest afr) {
        final Handler h = afr.getOnAudioFocusChangeListenerHandler();
        final FocusRequestInfo fri = new FocusRequestInfo(afr, (h == null) ? null :
            new ServiceEventHandlerDelegate(h).getHandler());
        final String key = getIdForAudioFocusListener(afr.getOnAudioFocusChangeListener());
        mAudioFocusIdListenerMap.put(key, fri);
    }
```

为什么单独说下这块呢，因为我们还记得上一篇我们在写AudioFocus的demo的时初始化AudioFocusReques的时候setOnAudioFocusChangeListener(mListener, mHandler)我们传入一个mHandler，这里用到了，那么它的作用是什么呢？其实决定的就是mListener的回调线程，如果不传mHandler那么默认回调到我们使用AudioManager申请焦点的这个线程，如果使用了mHander则回调到mHandler这个线程。建议不要规避开主线程。
那么我们继续分析AudioService

```java
    public int requestAudioFocus(AudioAttributes aa, int durationHint, IBinder cb,
            IAudioFocusDispatcher fd, String clientId, String callingPackageName, int flags,
            IAudioPolicyCallback pcb, int sdk) {

        if ((flags & AudioManager.AUDIOFOCUS_FLAG_LOCK) == AudioManager.AUDIOFOCUS_FLAG_LOCK) {
            if (AudioSystem.IN_VOICE_COMM_FOCUS_ID.equals(clientId)) {
                if (PackageManager.PERMISSION_GRANTED != mContext.checkCallingOrSelfPermission(
                            android.Manifest.permission.MODIFY_PHONE_STATE)) {
                    Log.e(TAG, "Invalid permission to (un)lock audio focus", new Exception());
                    return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
                }
            } else {

                synchronized (mAudioPolicies) {
                    if (!mAudioPolicies.containsKey(pcb.asBinder())) {
                        Log.e(TAG, "Invalid unregistered AudioPolicy to (un)lock audio focus");
                        return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
                    }
                }
            }
        }

        if (callingPackageName == null || clientId == null || aa == null) {
            Log.e(TAG, "Invalid null parameter to request audio focus");
            return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
        }

        return mMediaFocusControl.requestAudioFocus(aa, durationHint, cb, fd,
                clientId, callingPackageName, flags, sdk,
                forceFocusDuckingForAccessibility(aa, durationHint, Binder.getCallingUid()));
    }
```

大体也是分了三步
1.flag的检查，我们刚分析AudioManager的requestAudioFocus时已经看到了flag与audiopolicy的绑定判断，只不过到service又判断了一次，并详细说明了为何之前要绑定判断的原因，因为flag是lock的时候，如果不给电话用只能使用外部audiopolicy，所以之前要做与的判断。如果flag是lock状态并且给电话使用的话，那么我们就要使用requestAudioFocusForCall来申请。
2.参数判空的检查
3.调用了MediaFocusControl的requestAudioFocus

```java
    protected int requestAudioFocus(@NonNull AudioAttributes aa, int focusChangeHint, IBinder cb,
            IAudioFocusDispatcher fd, @NonNull String clientId, @NonNull String callingPackageName,
            int flags, int sdk, boolean forceDuck) {
        mEventLogger.log((new AudioEventLogger.StringEvent(
                "requestAudioFocus() from uid/pid " + Binder.getCallingUid()
                    + "/" + Binder.getCallingPid()
                    + " clientId=" + clientId + " callingPack=" + callingPackageName
                    + " req=" + focusChangeHint
                    + " flags=0x" + Integer.toHexString(flags)
                    + " sdk=" + sdk))
                .printLog(TAG));

        if (!cb.pingBinder()) {
            Log.e(TAG, " AudioFocus DOA client for requestAudioFocus(), aborting.");
            return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
        }

        if (mAppOps.noteOp(AppOpsManager.OP_TAKE_AUDIO_FOCUS, Binder.getCallingUid(),
                callingPackageName) != AppOpsManager.MODE_ALLOWED) {
            return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
        }

        synchronized(mAudioFocusLock) {

            if (mFocusStack.size() > MAX_STACK_SIZE) {
                Log.e(TAG, "Max AudioFocus stack size reached, failing requestAudioFocus()");
                return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
            }

            boolean enteringRingOrCall = !mRingOrCallActive
                    & (AudioSystem.IN_VOICE_COMM_FOCUS_ID.compareTo(clientId) == 0);
            if (enteringRingOrCall) { mRingOrCallActive = true; }

            final AudioFocusInfo afiForExtPolicy;

            if (mFocusPolicy != null) {

                afiForExtPolicy = new AudioFocusInfo(aa, Binder.getCallingUid(),
                        clientId, callingPackageName, focusChangeHint, 0 ,
                        flags, sdk);
            } else {
                afiForExtPolicy = null;
            }

            boolean focusGrantDelayed = false;

            if (!canReassignAudioFocus()) {
                if ((flags & AudioManager.AUDIOFOCUS_FLAG_DELAY_OK) == 0) {
                    return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
                } else {

                    focusGrantDelayed = true;
                }
            }

            if (mFocusPolicy != null) {
                if (notifyExtFocusPolicyFocusRequest_syncAf(afiForExtPolicy, fd, cb)) {

                    return AudioManager.AUDIOFOCUS_REQUEST_WAITING_FOR_EXT_POLICY;
                } else {

                    return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
                }
            }

            AudioFocusDeathHandler afdh = new AudioFocusDeathHandler(cb);

            try {
                cb.linkToDeath(afdh, 0);
            } catch (RemoteException e) {

                Log.w(TAG, "AudioFocus  requestAudioFocus() could not link to "+cb+" binder death");
                return AudioManager.AUDIOFOCUS_REQUEST_FAILED;
            }

            if (!mFocusStack.empty() && mFocusStack.peek().hasSameClient(clientId)) {

                final FocusRequester fr = mFocusStack.peek();
                if (fr.getGainRequest() == focusChangeHint && fr.getGrantFlags() == flags) {

                    cb.unlinkToDeath(afdh, 0);
                    notifyExtPolicyFocusGrant_syncAf(fr.toAudioFocusInfo(),
                            AudioManager.AUDIOFOCUS_REQUEST_GRANTED);
                    return AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
                }

                if (!focusGrantDelayed) {
                    mFocusStack.pop();

                    fr.release();
                }
            }

            removeFocusStackEntry(clientId, false , false );

            final FocusRequester nfr = new FocusRequester(aa, focusChangeHint, flags, fd, cb,
                    clientId, afdh, callingPackageName, Binder.getCallingUid(), this, sdk);
            if (focusGrantDelayed) {

                final int requestResult = pushBelowLockedFocusOwners(nfr);
                if (requestResult != AudioManager.AUDIOFOCUS_REQUEST_FAILED) {
                    notifyExtPolicyFocusGrant_syncAf(nfr.toAudioFocusInfo(), requestResult);
                }
                return requestResult;
            } else {

                if (!mFocusStack.empty()) {
                    propagateFocusLossFromGain_syncAf(focusChangeHint, nfr, forceDuck);
                }

                mFocusStack.push(nfr);
                nfr.handleFocusGainFromRequest(AudioManager.AUDIOFOCUS_REQUEST_GRANTED);
            }
            notifyExtPolicyFocusGrant_syncAf(nfr.toAudioFocusInfo(),
                    AudioManager.AUDIOFOCUS_REQUEST_GRANTED);

            if (ENFORCE_MUTING_FOR_RING_OR_CALL & enteringRingOrCall) {
                runAudioCheckerForRingOrCallAsync(true);
            }
        }

        return AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
    }
```

以上，其实申请焦点的过程基本到此就结束了，abandon就不多说了，再说下propagateFocusLossFromGain_syncAf(focusChangeHint, nfr, forceDuck)因为之前说过我们申请什么样音频焦点，能收到什么样的callback就是在这里处理的

```java
    private void propagateFocusLossFromGain_syncAf(int focusGain, final FocusRequester fr,
            boolean forceDuck) {
        final List<String> clientsToRemove = new LinkedList<String>();

        for (FocusRequester focusLoser : mFocusStack) {
            final boolean isDefinitiveLoss =
                    focusLoser.handleFocusLossFromGain(focusGain, fr, forceDuck);
            if (isDefinitiveLoss) {
                clientsToRemove.add(focusLoser.getClientId());
            }
        }
        for (String clientToRemove : clientsToRemove) {
            removeFocusStackEntry(clientToRemove, false ,
                    true );
        }
    }
```

我们看到根据申请的音频焦点来跟栈中所有的音频焦点做一个类似仲裁的处理，并把状态为loss的从焦点栈中移除，也就是说如果当前焦点中只有一个QQ音乐，那么我们此时申请一个优酷视频的音频焦点（他俩申请的类型相同），那么此时就会把QQ音乐从焦点栈中移除，具体逻辑继续看

```java
    boolean handleFocusLossFromGain(int focusGain, final FocusRequester frWinner, boolean forceDuck)
    {
        final int focusLoss = focusLossForGainRequest(focusGain);
        handleFocusLoss(focusLoss, frWinner, forceDuck);
        return (focusLoss == AudioManager.AUDIOFOCUS_LOSS);
    }
```

在看下focusLossForGainRequest

```java
    private int focusLossForGainRequest(int gainRequest) {

        switch(gainRequest) {
            case AudioManager.AUDIOFOCUS_GAIN:

                switch(mFocusLossReceived) {
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                    case AudioManager.AUDIOFOCUS_LOSS:
                    case AudioManager.AUDIOFOCUS_NONE:
                        return AudioManager.AUDIOFOCUS_LOSS;
                }
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE:
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT:
                switch(mFocusLossReceived) {
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                    case AudioManager.AUDIOFOCUS_NONE:
                        return AudioManager.AUDIOFOCUS_LOSS_TRANSIENT;
                    case AudioManager.AUDIOFOCUS_LOSS:
                        return AudioManager.AUDIOFOCUS_LOSS;
                }
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK:
                switch(mFocusLossReceived) {
                    case AudioManager.AUDIOFOCUS_NONE:
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                        return AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK;
                    case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                        return AudioManager.AUDIOFOCUS_LOSS_TRANSIENT;
                    case AudioManager.AUDIOFOCUS_LOSS:
                        return AudioManager.AUDIOFOCUS_LOSS;
                }
            default:
                Log.e(TAG, "focusLossForGainRequest() for invalid focus request "+ gainRequest);
                        return AudioManager.AUDIOFOCUS_NONE;
        }
    }
```

原来用了两个switch/case处理所用音频焦点的可能情况。举个例子说明一下我们先申请了一个AUDIOFOCUS_GAIN的焦点，第一次肯定成功，那么第二次我们在申请一个AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK的焦点，那么第一次申请的焦点会对应收到AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK这么一个callback并把这个值更新给了第一次申请的焦点的mFocusLossReceived，在比如如我们先申请一个AUDIOFOCUS_GAIN成功了，在申请一个AUDIOFOCUS_GAIN_TRANSIENT，那么第一次申请的焦点会收到AudioManager.AUDIOFOCUS_LOSS_TRANSIENT这么一个callback，

申请音频焦点的逻辑基本整个流程就这样的，从AudioManager–>AudioServicer–>MediaFocusControl.最终将申请结果根据我们申请的类型做两个switch/case的判断后返回。如果有问题欢迎大家一起沟通解决~
