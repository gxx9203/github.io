---
link: https://blog.csdn.net/l328873524/article/details/102964876
title: Android9.0CarAudio分析之一启动过程
description: 2019年还有不到俩月就结束了，匆匆忙忙慌慌张张又是没有收获的一年，三十好几的大龄程序员，年初信誓旦旦定下养成写博客的习惯的我，看来今年又食言了。以前在思否写过一点东西，但今天还是决定回到csdn，借着19年的尾巴，从0开始。正题我们知道谷歌为汽车单独搞了一套，但由于不是很成熟，因此每个版本变更时Car这部分都会有很大变化，因此为了方便理解，基于Android9.0简单分析下CarAudio...
keywords: Android9.0CarAudio分析之一启动过程
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2019-11-07T15:36:00.000Z
publisher: null
stats: paragraph=25 sentences=45, words=321
tags:
    - CSDN转载
    - Audio
---
2019年还有不到俩月就结束了，匆匆忙忙慌慌张张又是没有收获的一年，三十好几的大龄程序员，年初信誓旦旦定下养成写博客的习惯的我，看来今年又食言了。
以前在思否写过一点东西，但今天还是决定回到csdn，借着19年的尾巴，从0开始。

我们知道谷歌为汽车单独搞了一套，但由于不是很成熟，因此每个版本变更时Car这部分都会有很大变化，因此为了方便理解，基于Android9.0简单分析下CarAudio这部分

Android系统的启动就不做累赘了，就从SystemServer的起动过程开始说起吧，看下main函数，学习过java的人都明白main函数的作用吧。

```java
public static void main(String[] args) {
new SystemServer().run();
}
```

在run()中有两部分代码我们先关注下这段代码

```java

mSystemServiceManager = new SystemServiceManager(mSystemContext);
mSystemServiceManager.setStartInfo(mRuntimeRestart,
mRuntimeStartElapsedTime, mRuntimeStartUptime);

try {
    traceBeginAndSlog("StartServices");
    startBootstrapServices();
    startCoreServices();
    startOtherServices();
    SystemServerInitThreadPool.shutdown();
} catch (Throwable ex) {
    Slog.e("System", "******************************************");
    Slog.e("System", "************ Failure starting system services", ex);
    throw ex;
} finally {
    traceEnd();
}
```

从字面看除了 new 一个 SystemServiceManager好像是start了很多service，确实如此。但我们今天只说说startOtherServices()中的StartCarServiceHelperService，代码如下

```java
if (mPackageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)) {
    traceBeginAndSlog("StartCarServiceHelperService");
    mSystemServiceManager.startService(CAR_SERVICE_HELPER_SERVICE_CLASS);
    traceEnd();
}
```

在简单了看下mSystemServiceManager.startService的过程

```java
    public void startService(@NonNull final SystemService service) {

        mServices.add(service);

        long time = SystemClock.elapsedRealtime();
        try {
            service.onStart();
        } catch (RuntimeException ex) {
            throw new RuntimeException("Failed to start service " + service.getClass().getName()
                    + ": onStart threw an exception", ex);
        }
        warnIfTooLong(SystemClock.elapsedRealtime() - time, service, "onStart");
    }
```

其实就是调用了service的onstart方法，那么我们去CarServiceHelperService中看看onstart方法中做了什么
frameworks/opt/car/services/src/com/android/internal/car/CarServiceHelperService.java

```java
    @Override
    public void onStart() {
        Intent intent = new Intent();
        intent.setPackage("com.android.car");
        intent.setAction(CAR_SERVICE_INTERFACE);
        if (!getContext().bindServiceAsUser(intent, mCarServiceConnection, Context.BIND_AUTO_CREATE,
                UserHandle.SYSTEM)) {
            Slog.wtf(TAG, "cannot start car service");
        }
        System.loadLibrary("car-framework-service-jni");
    }
```

原来只是去bind了CarService,继续去CarService的bind过程
packages/services/Car/service/src/com/android/car/CarService.java

```java
packages/services/Car/service/src/com/android/car/CarService.java
    public void onCreate() {
        Log.i(CarLog.TAG_SERVICE, "Service onCreate");
        mCanBusErrorNotifier = new CanBusErrorNotifier(this );

        mVehicle = getVehicle();

        if (mVehicle == null) {
            throw new IllegalStateException("Vehicle HAL service is not available.");
        }
        try {
            mVehicleInterfaceName = mVehicle.interfaceDescriptor();
        } catch (RemoteException e) {
            throw new IllegalStateException("Unable to get Vehicle HAL interface descriptor", e);
        }

        Log.i(CarLog.TAG_SERVICE, "Connected to " + mVehicleInterfaceName);

        mICarImpl = new ICarImpl(this,
                mVehicle,
                SystemInterface.Builder.defaultSystemInterface(this).build(),
                mCanBusErrorNotifier,
                mVehicleInterfaceName);
        mICarImpl.init();
}
```

我们继续查看ICarImpl的初始化
/packages/services/Car/service/src/com/android/car/ICarImpl.java
在IcarImpl的构造函数中发现 new了好多对象，然后再把每一个都init了，IcarImpl的构造函数的代码太长就不贴了，只列出一个即今天的主角mCarAudioService = new CarAudioService(serviceContext)，我们在看一下init的方法：

```java
    void init() {
        traceBegin("VehicleHal.init");
        mHal.init();
        traceEnd();
        traceBegin("CarService.initAllServices");
        for (CarServiceBase service : mAllServices) {
            service.init();
        }
        traceEnd();
    }
```

通过一个for循环调用了所有子类的init。其实CarAudioService也是CarServiceBase的一个子类，ok，下次继续分析CarAudioService的init都做了什么。
