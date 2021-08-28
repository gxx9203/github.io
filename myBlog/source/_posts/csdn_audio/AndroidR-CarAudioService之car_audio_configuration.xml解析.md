---
link: https://blog.csdn.net/l328873524/article/details/113959900
title: Android R- CarAudioService之car_audio_configuration.xml解析
description: 前言关于car_audio_configuration.xml的解析这部分在Android R上还是有一点变化的。具体我们一步一步来分析下其解析原理和过程。car_audio_configuration.xml
keywords: Android R- CarAudioService之car_audio_configuration.xml解析
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2021-03-14T16:51:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=91 sentences=136, words=1006
---
## 前言

关于car_audio_configuration.xml的解析这部分在Android R上还是有一点变化的。具体我们一步一步来分析下其解析原理和过程。

## car_audio_configuration.xml

首先关于这个xml配置文件的位置，aosp的源码位置为/device/generic/car/emulator/audio/car_emulator_audio.mk，当然也可具体根据自己的情况来定,反正最后放到车机的路径是固定的，具体如下

```c
     device/generic/car/emulator/audio/car_audio_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/car_audio_configuration.xml
```

然后看下这个配置文件里面的内容

```xml

<carAudioConfiguration version="2">
    <zones>
        <zone name="primary zone" isPrimary="true" occupantZoneId="0">
            <volumeGroups>
                <group>
                    <device address="bus0_media_out">
                        <context context="music"/>
                    device>
                    <device address="bus3_call_ring_out">
                        <context context="call_ring"/>
                    device>
                    <device address="bus6_notification_out">
                        <context context="notification"/>
                    device>
                    <device address="bus7_system_sound_out">
                        <context context="system_sound"/>
                        <context context="emergency"/>
                        <context context="safety"/>
                        <context context="vehicle_status"/>
                        <context context="announcement"/>
                    device>
                group>
                <group>
                    <device address="bus1_navigation_out">
                        <context context="navigation"/>
                    device>
                    <device address="bus2_voice_command_out">
                        <context context="voice_command"/>
                    device>
                group>
                <group>
                    <device address="bus4_call_out">
                        <context context="call"/>
                    device>
                group>
                <group>
                    <device address="bus5_alarm_out">
                        <context context="alarm"/>
                    device>
                group>
            volumeGroups>
        zone>
        <zone name="rear seat zone 1" audioZoneId="1">
            <volumeGroups>
                <group>
                    <device address="bus100_audio_zone_1">
                        <context context="music"/>
                        <context context="navigation"/>
                        <context context="voice_command"/>
                        <context context="call_ring"/>
                        <context context="call"/>
                        <context context="alarm"/>
                        <context context="notification"/>
                        <context context="system_sound"/>
                        <context context="emergency"/>
                        <context context="safety"/>
                        <context context="vehicle_status"/>
                        <context context="announcement"/>
                    device>
                group>
            volumeGroups>
        zone>
        <zone name="rear seat zone 2"  audioZoneId="2">
            <volumeGroups>
                <group>
                    <device address="bus200_audio_zone_2">
                        <context context="music"/>
                        <context context="navigation"/>
                        <context context="voice_command"/>
                        <context context="call_ring"/>
                        <context context="call"/>
                        <context context="alarm"/>
                        <context context="notification"/>
                        <context context="system_sound"/>
                        <context context="emergency"/>
                        <context context="safety"/>
                        <context context="vehicle_status"/>
                        <context context="announcement"/>
                    device>
                group>
            volumeGroups>
        zone>
    zones>
carAudioConfiguration>
```

从xml的注释就看出来来了，这个配置文件主要有

* Audio zones
* Context to audio bus mappings
* Volume groups
这三个功能，首先说下Audio Zones，通过xml可以看到有primary zone和"rear seat zone 1和"rear seat zone 2一共三个Zone。首先看下Zone的加载时序
![](https://img-blog.csdnimg.cn/20210225011737827.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70#pic_center)
在CaeAudioService启动的时候，会调用 setupDynamicRoutingLocked进行动态路由的注册，注册前首先会解析这个xml，即调用 loadCarAudioZonesLocked，我们看下源码

```cpp
    private void loadCarAudioZonesLocked() {

        List<CarAudioDeviceInfo> carAudioDeviceInfos = generateCarAudioDeviceInfos();

        mCarAudioConfigurationPath = getAudioConfigurationPath();
        if (mCarAudioConfigurationPath != null) {

            mCarAudioZones = loadCarAudioConfigurationLocked(carAudioDeviceInfos);
        } else {
            mCarAudioZones = loadVolumeGroupConfigurationWithAudioControlLocked(
                    carAudioDeviceInfos);
        }

        CarAudioZonesValidator.validate(mCarAudioZones);
    }
```

具体关于CarAudioDeviceInfo都有哪些，这里不细说了，可以参照之前的分析。其实这些Devices的信息都是来自audio_policy_configuration.xml中的devicePort下type为AUDIO_DEVICE_OUT_BUS的Device，这个Device的type全部为AUDIO_DEVICE_OUT_BUS，而且address都是以bus+数字开头的。
接下来具体看下CarAudioZone是如何解析的，继续看loadCarAudioConfigurationLocked()

```java
    private SparseArray<CarAudioZone> loadCarAudioConfigurationLocked(
            List<CarAudioDeviceInfo> carAudioDeviceInfos) {

        AudioDeviceInfo[] inputDevices = getAllInputDevices();
        try (InputStream inputStream = new FileInputStream(mCarAudioConfigurationPath)) {

            CarAudioZonesHelper zonesHelper = new CarAudioZonesHelper(mCarAudioSettings,
                    inputStream, carAudioDeviceInfos, inputDevices);

            mAudioZoneIdToOccupantZoneIdMapping =
                    zonesHelper.getCarAudioZoneIdToOccupantZoneIdMapping();

            return zonesHelper.loadAudioZones();
        } catch (IOException | XmlPullParserException e) {
            throw new RuntimeException("Failed to parse audio zone configuration", e);
        }
    }
```

这里说下inputDevices，之前的carAudioDeviceInfos找到主要是输出设备即device的role = sink，而inputDevices 则找到主要是输入设备即device的role = source，对应的type = AUDIO_DEVICE_IN_BUS。
拿到输出和输入设备以及xml的path，把这些给到CarAudioZonesHelper来做解析和初始化。
略过CarAudioZonesHelper的构造函数，直接进入loadAudioZones（）。

```java
    SparseArray<CarAudioZone> loadAudioZones() throws IOException, XmlPullParserException {

        return parseCarAudioZones(mInputStream);
    }
```

继续看parseCarAudioZones(),即开始真正的解析。

```java
    private SparseArray<CarAudioZone> parseCarAudioZones(InputStream stream)
            throws XmlPullParserException, IOException {
          ........

        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;

            if (TAG_AUDIO_ZONES.equals(parser.getName())) {

                return parseAudioZones(parser);
            } else {
                skip(parser);
            }
        }
        throw new RuntimeException(TAG_AUDIO_ZONES + " is missing from configuration");
    }
```

通过xml可以看到只有一组 zones标签，即while只执行一次parseAudioZones

```java
    private SparseArray<CarAudioZone> parseAudioZones(XmlPullParser parser)
            throws XmlPullParserException, IOException {

        SparseArray<CarAudioZone> carAudioZones = new SparseArray<>();

        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;

            if (TAG_AUDIO_ZONE.equals(parser.getName())) {

                CarAudioZone zone = parseAudioZone(parser);

                verifyOnlyOnePrimaryZone(zone, carAudioZones);

                carAudioZones.put(zone.getId(), zone);
            } else {
                skip(parser);
            }
        }

        verifyPrimaryZonePresent(carAudioZones);

        return carAudioZones;
    }
```

这里开始解析zone标签，通过xml可以看到这里有三组zone分别是primary zone 、rear seat zone 1和rear seat zone 2，
要调用三次parseAudioZone(parser)即创建三个CarAudioZone。继续看parseAudioZone()

```java
    private CarAudioZone parseAudioZone(XmlPullParser parser)
            throws XmlPullParserException, IOException {

        final boolean isPrimary = Boolean.parseBoolean(
                parser.getAttributeValue(NAMESPACE, ATTR_IS_PRIMARY));

        final String zoneName = parser.getAttributeValue(NAMESPACE, ATTR_ZONE_NAME);

        final int audioZoneId = getZoneId(isPrimary, parser);

        parseOccupantZoneId(audioZoneId, parser);

        final CarAudioZone zone = new CarAudioZone(audioZoneId, zoneName);
        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;

            if (TAG_VOLUME_GROUPS.equals(parser.getName())) {

                parseVolumeGroups(parser, zone);
            } else if (TAG_INPUT_DEVICES.equals(parser.getName())) {

                parseInputAudioDevices(parser, zone);
            } else {
                skip(parser);
            }
        }
        return zone;
    }
```

zoneName 的获取直接通过解析对应的属性就拿到了，简单说下audioZoneId，我们看到了不是直接去解析xml而是调用了getZoneId(isPrimary, parser)函数，其实这个函数对primary zone做了特殊处理。如果我们传入的isPrimary是true，那么它的audioZoneId就是0即PRIMARY_AUDIO_ZONE。因此这个xml里对于primary zone也就未定义audioZoneId。这里还对primary zone的 audioZoneId做了强制要求就是如果我们定义了audioZoneId， **它的值必须必须是0，而且其他zoneId不可以定义0.**
再说下parseOccupantZoneId(audioZoneId, parser)，这个Android R新增的。这里是解析occupantZoneId然后把它和audioZoneId一起放到map中，即 mZoneIdToOccupantZoneIdMapping.put(audioZoneId, occupantZoneId)，occupantZoneId不能重复，但还没看到是否可以定义多个，以及occupantZoneId是否也是必须是从0开始。但是一般只定义一个，如 occupantZoneId="0"这样。
最后关于这个函数再看下CarAudioZone的定义

```java
    CarAudioZone(int id, String name) {
        mId = id;
        mName = name;
        mVolumeGroups = new ArrayList<>();
        mInputAudioDevice = new ArrayList<>();
    }
```

好的继续看VolumeGroups的解析，这个算是重点了。

```java
    private void parseVolumeGroups(XmlPullParser parser, CarAudioZone zone)
            throws XmlPullParserException, IOException {
        int groupId = 0;
        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;
            if (TAG_VOLUME_GROUP.equals(parser.getName())) {

                zone.addVolumeGroup(parseVolumeGroup(parser, zone.getId(), groupId));

                groupId++;
            } else {
                skip(parser);
            }
        }

```

这里分析下primary zone的group解析，其他zone相同，primary zone里共有四组group，我们先看第一组group的解析parseVolumeGroup(parser, zone.getId(), groupId)

```java
    private CarVolumeGroup parseVolumeGroup(XmlPullParser parser, int zoneId, int groupId)
            throws XmlPullParserException, IOException {

        CarVolumeGroup group = new CarVolumeGroup(mCarAudioSettings, zoneId, groupId);
        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;

            if (TAG_AUDIO_DEVICE.equals(parser.getName())) {

                String address = parser.getAttributeValue(NAMESPACE, ATTR_DEVICE_ADDRESS);

                validateOutputDeviceExist(address);

                parseVolumeGroupContexts(parser, group, address);
            } else {
                skip(parser);
            }
        }
        return group;
    }
```

这里开始解析volumeGroup了，这块先看下时序图
![](https://img-blog.csdnimg.cn/20210314234551357.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L2wzMjg4NzM1MjQ=,size_16,color_FFFFFF,t_70)
时序画的简单些了，具体看下每个过程，主要这个函数parseVolumeGroupContexts()，我们知道car_audio_configuration.xml这个xml做了三件事，其中这个就是Volume groups。我们再具体看下这个函数：

```java
    private void parseVolumeGroupContexts(
            XmlPullParser parser, CarVolumeGroup group, String address)
            throws XmlPullParserException, IOException {
        while (parser.next() != XmlPullParser.END_TAG) {
            if (parser.getEventType() != XmlPullParser.START_TAG) continue;
            if (TAG_CONTEXT.equals(parser.getName())) {

                @AudioContext int carAudioContext = parseCarAudioContext(
                        parser.getAttributeValue(NAMESPACE, ATTR_CONTEXT_NAME));

                validateCarAudioContextSupport(carAudioContext);

                CarAudioDeviceInfo info = mAddressToCarAudioDeviceInfo.get(address);

                group.bind(carAudioContext, info);

                if (isVersionOne() && carAudioContext == CarAudioService.DEFAULT_AUDIO_CONTEXT) {
                    bindNonLegacyContexts(group, info);
                }
            }

            skip(parser);
        }
    }
```

首先说下carAudioContext是怎么取到的，因为xml给的是一个string，这里是int，肯定是在哪里做了映射，映射的地方如下

```java
    static {
        CONTEXT_NAME_MAP = new HashMap<>(CarAudioContext.CONTEXTS.length);
        CONTEXT_NAME_MAP.put("music", CarAudioContext.MUSIC);
        CONTEXT_NAME_MAP.put("navigation", CarAudioContext.NAVIGATION);
        CONTEXT_NAME_MAP.put("voice_command", CarAudioContext.VOICE_COMMAND);
        CONTEXT_NAME_MAP.put("call_ring", CarAudioContext.CALL_RING);
        CONTEXT_NAME_MAP.put("call", CarAudioContext.CALL);
        CONTEXT_NAME_MAP.put("alarm", CarAudioContext.ALARM);
        CONTEXT_NAME_MAP.put("notification", CarAudioContext.NOTIFICATION);
        CONTEXT_NAME_MAP.put("system_sound", CarAudioContext.SYSTEM_SOUND);
        CONTEXT_NAME_MAP.put("emergency", CarAudioContext.EMERGENCY);
        CONTEXT_NAME_MAP.put("safety", CarAudioContext.SAFETY);
        CONTEXT_NAME_MAP.put("vehicle_status", CarAudioContext.VEHICLE_STATUS);
        CONTEXT_NAME_MAP.put("announcement", CarAudioContext.ANNOUNCEMENT);

        SUPPORTED_VERSIONS = new SparseIntArray(2);
        SUPPORTED_VERSIONS.put(SUPPORTED_VERSION_1, SUPPORTED_VERSION_1);
        SUPPORTED_VERSIONS.put(SUPPORTED_VERSION_2, SUPPORTED_VERSION_2);
    }
```

这样我们就拿到了carAudioContext，完事CarAudioDeviceInfo的获取就不说了（上面说过了）拿到info和contex后一起传给了CarVolumeGroup的bind

```java
    void bind(int carAudioContext, CarAudioDeviceInfo info) {
        Preconditions.checkArgument(mContextToAddress.get(carAudioContext) == null,
                String.format("Context %s has already been bound to %s",
                        CarAudioContext.toString(carAudioContext),
                        mContextToAddress.get(carAudioContext)));

        synchronized (mLock) {

            if (mAddressToCarAudioDeviceInfo.size() == 0) {

                mStepSize = info.getStepValue();
            } else {

                Preconditions.checkArgument(
                        info.getStepValue() == mStepSize,
                        "Gain controls within one group must have same step value");
            }

            mAddressToCarAudioDeviceInfo.put(info.getAddress(), info);

            mContextToAddress.put(carAudioContext, info.getAddress());

            if (info.getDefaultGain() > mDefaultGain) {

                mDefaultGain = info.getDefaultGain();
            }

            if (info.getMaxGain() > mMaxGain) {
                mMaxGain = info.getMaxGain();
            }

            if (info.getMinGain() < mMinGain) {
                mMinGain = info.getMinGain();
            }

            updateCurrentGainIndexLocked();
        }
    }
```

bind是一个很重要的函数，主要是给音量分组，更新当前组音量的最大/小值，默认值以及当前音量值。并且维护了两个很重要的的map是 **mAddressToCarAudioDeviceInfo**（address为key，CarAudioDeviceInfo 为value）和 **mContextToAddress**(context是key，address是value),其实有了这两个map我们就可以根据context找到address，根据address找到CarAudioDeviceInfo 。把context和CarAudioDeviceInfo 路由在了一起。
我们继续再回头看下 CarVolumeGroup里还有什么， mZoneId 和mId(groupId)，这样一个CarVolumeGroup对应的zoneId以及自己的Id和内部维护的context以及CarAudioDeviceInfo 就全部关联上了。

## 总结

其实到这里整个xml基本就要解析完成了，回顾下这三步：

* Audio zones
有三个zone，一个primary zone也是occupant Zone
* Context to audio bus mappings
在解析VolumeGroup时将context和CarAudioDeviceInfo mapping到一起了，具体就是bind中做的
* Volume groups
每个zone都至少有个volumeGroups，同一个volumeGroups里有几个group就有几组音量。同一组的音量相同。
这个car_audio_configuration.xml看似很简单，但是如果我们在项目中需要定制，需要修改某一部分一定要多注意，因为每个标签的属性都是有一定的关联和限定的。
下一次继续分析解析car_audio_configuration.xml后做的动态路由，以及多音区的焦点管理。
