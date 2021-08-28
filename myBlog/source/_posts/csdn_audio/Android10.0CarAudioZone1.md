---
link: https://blog.csdn.net/l328873524/article/details/105803330
title: Android10.0CarAudioZone（一）
description: 前言关于CarAudioZone也就是多音区的一个概念，主要是在AndroidQ上实现的。我们可以参照官方的文档Multi-Zone Overview我的英语实在不敢恭维，这里就不翻译了，大家阅读自行翻译吧。我简单描述下多音区的概念，就是这么一种环境，后排乘客通过后排屏幕可以看电影，前排司机通过前排屏幕可以听音乐，大家互不影响。每一个屏都有自己专属的一个区域也就是zone的概念。这种前后屏的概念...
keywords: Android10.0CarAudioZone（一）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-04-30T15:09:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=64 sentences=115, words=969
---
关于CarAudioZone也就是多音区的一个概念，主要是在AndroidQ上实现的。我们可以参照官方的文档[Multi-Zone Overview](https://source.android.google.cn/devices/automotive/audio/multi_zone/overview)，我的英语实在不敢恭维，这里就不翻译了，大家阅读自行翻译吧。我简单描述下多音区的概念，就是这么一种环境，后排乘客通过后排屏幕可以看电影，前排司机通过前排屏幕可以听音乐，大家互不影响。每一个屏都有自己专属的一个区域也就是zone的概念。这种前后屏的概念可能在的一些士的上体现的更好，我记得我曾经去过一个城市，乘客坐后排通过后座的屏幕可以了解这个城市的旅游景点，文化特色等，而前排司机就可以不受干扰的听他的交通广播了，扯远了哈，其实这种场景还有一种使用场景就是带主副屏的车机，比如现在好多汽车都是主副屏联动的，有了这个，我们都可以参照来实现了。

今天还是从源码的角度来分析carAudioZone这块，我们也是从CarAudioService中开始说吧，虽然之前分析了[Android9.0CarAudio分析之一启动过程](https://blog.csdn.net/l328873524/article/details/102964876)但我们今天基于Android10.0在来看看CarAudioZone这块。首先

```java
private final boolean mUseDynamicRouting;
```

如果想使用CarAudioZone这套，mUseDynamicRouting一定要设置为true。这个值是来自

```java
packages/services/Car/service/res/values/config.xml
<bool name="audioUseDynamicRouting">false</bool>
```

中，我们发现默认是false，但我们一般很少去改动原生目录下的配置，建议通过overlay的方式实现。 **如果audioUseDynamicRouting为false，则CarAudio中的逻辑就会走到Android原生的AudioManager和AudioService中去了。这也算是一个兼容处理吧**
我们先看下CarAudioService的构造函数

```java
    public CarAudioService(Context context) {
        mContext = context;
        mTelephonyManager = (TelephonyManager) mContext.getSystemService(Context.TELEPHONY_SERVICE);
        mAudioManager = (AudioManager) mContext.getSystemService(Context.AUDIO_SERVICE);
        mUseDynamicRouting = mContext.getResources().getBoolean(R.bool.audioUseDynamicRouting);
        mPersistMasterMuteState = mContext.getResources().getBoolean(
                R.bool.audioPersistMasterMuteState);
        mUidToZoneMap = new HashMap<>();
    }
```

相比之前版本多了mUidToZoneMap，一个map的集合定义如下

```java
private Map<Integer, Integer> mUidToZoneMap;
```

这个后续我们用到在细说，构造函数结束就是init了

```java
    public void init() {
        synchronized (mImplLock) {
            if (mUseDynamicRouting) {

                AudioDeviceInfo[] deviceInfos = mAudioManager.getDevices(
                        AudioManager.GET_DEVICES_OUTPUTS);
                if (deviceInfos.length == 0) {
                    Log.e(CarLog.TAG_AUDIO, "No output device available, ignore");
                    return;
                }
                SparseArray<CarAudioDeviceInfo> busToCarAudioDeviceInfo = new SparseArray<>();
                for (AudioDeviceInfo info : deviceInfos) {
                    Log.v(CarLog.TAG_AUDIO, String.format("output id=%d address=%s type=%s",
                            info.getId(), info.getAddress(), info.getType()));
                    if (info.getType() == AudioDeviceInfo.TYPE_BUS) {
                        final CarAudioDeviceInfo carInfo = new CarAudioDeviceInfo(info);

                        if (carInfo.getBusNumber() >= 0) {
                            busToCarAudioDeviceInfo.put(carInfo.getBusNumber(), carInfo);
                            Log.i(CarLog.TAG_AUDIO, "Valid bus found " + carInfo);
                        }
                    }
                }
                setupDynamicRouting(busToCarAudioDeviceInfo);
            } else {
                Log.i(CarLog.TAG_AUDIO, "Audio dynamic routing not enabled, run in legacy mode");
                setupLegacyVolumeChangedListener();
            }

            if (mPersistMasterMuteState) {
                boolean storedMasterMute = Settings.Global.getInt(mContext.getContentResolver(),
                        VOLUME_SETTINGS_KEY_MASTER_MUTE, 0) != 0;
                setMasterMute(storedMasterMute, 0);
            }
        }
    }
```

init逻辑分了几个阶段第一个阶段是找output device。关于找output device的逻辑可参照[Android10.0AudioFocus之如何使用（一）](https://blog.csdn.net/l328873524/article/details/105189766)和二。然后根据deviceType是TYPE_BUS的拿出来在重新封装到CarAudioDeviceInfo中，我们在getDevices的时候，还记得有的device是AUDIO_DEVICE_OUT_BUS，所有使用AUDIO_DEVICE_OUT_BUS的都会有个address，而且address一定是不相同的。其实这里过滤的就是这个deviceType是AUDIO_DEVICE_OUT_BUS的即

```java
public static final int DEVICE_OUT_BUS = 0x1000000;
```

我们在简单看下CarAudioDeviceInfo吧

```java
    CarAudioDeviceInfo(AudioDeviceInfo audioDeviceInfo) {
        mAudioDeviceInfo = audioDeviceInfo;
        mBusNumber = parseDeviceAddress(audioDeviceInfo.getAddress());
        mSampleRate = getMaxSampleRate(audioDeviceInfo);
        mEncodingFormat = getEncodingFormat(audioDeviceInfo);
        mChannelCount = getMaxChannels(audioDeviceInfo);
        final AudioGain audioGain = Preconditions.checkNotNull(
                getAudioGain(), "No audio gain on device port " + audioDeviceInfo);
        mDefaultGain = audioGain.defaultValue();
        mMaxGain = audioGain.maxValue();
        mMinGain = audioGain.minValue();

        mCurrentGain = -1;
    }
```

说下mBusNumber 这个我们看下audio_policy_volumes.xml中的定义就明白了

```cpp
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

mBusNumber 就是取得bus0_media_out，这个是怎么截取的呢，源码就不贴了，找到bus和第一个"_"中间的字符截取出来转成int，比如这个mBusNumber 就是0，关于截取这个最大是三位，像之前的版本都是bus00X_XXXX的。采样率 channel数都是根据配置来的，AudioGain是控制音量的。
我们继续，拿到了CarAudioDeviceInfo的集合后，则调用了setupDynamicRouting(busToCarAudioDeviceInfo)方法，代码很长，我们一点一点分析

```java
  private void setupDynamicRouting(SparseArray<CarAudioDeviceInfo> busToCarAudioDeviceInfo) {

        final AudioPolicy.Builder builder = new AudioPolicy.Builder(mContext);
        builder.setLooper(Looper.getMainLooper());

        mCarAudioConfigurationPath = getAudioConfigurationPath();
        if (mCarAudioConfigurationPath != null) {
            try (InputStream inputStream = new FileInputStream(mCarAudioConfigurationPath)) {
                CarAudioZonesHelper zonesHelper = new CarAudioZonesHelper(mContext, inputStream,
                        busToCarAudioDeviceInfo);
                mCarAudioZones = zonesHelper.loadAudioZones();
            } catch (IOException | XmlPullParserException e) {
                throw new RuntimeException("Failed to parse audio zone configuration", e);
            }
        } else {

            final IAudioControl audioControl = getAudioControl();
            if (audioControl == null) {
                throw new RuntimeException(
                        "Dynamic routing requested but audioControl HAL not available");
            }
            CarAudioZonesHelperLegacy legacyHelper = new CarAudioZonesHelperLegacy(mContext,
                    R.xml.car_volume_groups, busToCarAudioDeviceInfo, audioControl);
            mCarAudioZones = legacyHelper.loadAudioZones();
        }
        for (CarAudioZone zone : mCarAudioZones) {
            if (!zone.validateVolumeGroups()) {
                throw new RuntimeException("Invalid volume groups configuration");
            }

            zone.synchronizeCurrentGainIndex();
            Log.v(CarLog.TAG_AUDIO, "Processed audio zone: " + zone);
        }

        final CarAudioDynamicRouting dynamicRouting = new CarAudioDynamicRouting(mCarAudioZones);
        dynamicRouting.setupAudioDynamicRouting(builder);

        builder.setAudioPolicyVolumeCallback(mAudioPolicyVolumeCallback);

        if (sUseCarAudioFocus) {

            mFocusHandler = new CarZonesAudioFocus(mAudioManager,
                    mContext.getPackageManager(),
                    mCarAudioZones);
            builder.setAudioPolicyFocusListener(mFocusHandler);
            builder.setIsAudioFocusPolicy(true);
        }

        mAudioPolicy = builder.build();
        if (sUseCarAudioFocus) {

            mFocusHandler.setOwningPolicy(this, mAudioPolicy);
        }

        int r = mAudioManager.registerAudioPolicy(mAudioPolicy);
        if (r != AudioManager.SUCCESS) {
            throw new RuntimeException("registerAudioPolicy failed " + r);
        }
    }
```

我们一点一点分析，先看下获取getAudioConfigurationPath();

```java
       private static final String[] AUDIO_CONFIGURATION_PATHS = new String[] {
            "/vendor/etc/car_audio_configuration.xml",
            "/system/etc/car_audio_configuration.xml"
    };
    private String getAudioConfigurationPath() {
        for (String path : AUDIO_CONFIGURATION_PATHS) {
            File configuration = new File(path);
            if (configuration.exists()) {
                return path;
            }
        }
        return null;
    }
```

首先加载vendor/etc下的，如果vendor/etc没有则加载system/etc，android系统中一般配置文件都是这么一个加载顺序，先加载vendor下，如果没有，在加载系统默认的。拿到path后则开始解析

```java
 try (InputStream inputStream = new FileInputStream(mCarAudioConfigurationPath)) {
                CarAudioZonesHelper zonesHelper = new CarAudioZonesHelper(mContext, inputStream,
                        busToCarAudioDeviceInfo);
                mCarAudioZones = zonesHelper.loadAudioZones();
            } catch (IOException | XmlPullParserException e) {
                throw new RuntimeException("Failed to parse audio zone configuration", e);
            }
```

我们继续看下CarAudioZonesHelper的创建和它的loadAudioZones()过程。

```java
    CarAudioZonesHelper(Context context, @NonNull InputStream inputStream,
            @NonNull SparseArray<CarAudioDeviceInfo> busToCarAudioDeviceInfo) {
        mContext = context;
        mInputStream = inputStream;
        mBusToCarAudioDeviceInfo = busToCarAudioDeviceInfo;

        mNextSecondaryZoneId = CarAudioManager.PRIMARY_AUDIO_ZONE + 1;
        mPortIds = new HashSet<>();
    }
```

构造方法很简单，做了一些初始化，继续看load

```java
    CarAudioZone[] loadAudioZones() throws IOException, XmlPullParserException {
        List<CarAudioZone> carAudioZones = new ArrayList<>();
        parseCarAudioZones(carAudioZones, mInputStream);
        return carAudioZones.toArray(new CarAudioZone[0]);
    }
```

这里主要是对刚传入path的一个解析，为了理解解析的过程，我把car_audio_configuration.xml贴出来

```c
<?xml version="1.0" encoding="utf-8"?>
<carAudioConfiguration version="1">
    <zones>
        <zone name="primary zone" isPrimary="true">
            <volumeGroups>
                <group>
                    <device address="bus0_media_out">
                        <context context="music"/>
                    </device>
                    <device address="bus3_call_ring_out">
                        <context context="call_ring"/>
                    </device>
                </group>
                <group>
                    <device address="bus1_navigation_out">
                        <context context="navigation"/>
                    </device>
                </group>
            </volumeGroups>
            <displays>
                <display port="1"/>
                <display port="2"/>
            </displays>
        </zone>
        <zone name="rear seat zone">
            <volumeGroups>
                <group>
                    <device address="bus100_rear_seat">
                        <context context="music"/>
                        <context context="navigation"/>
                        <context context="voice_command"/>
                        <context context="call_ring"/>
                        <context context="call"/>
                        <context context="alarm"/>
                        <context context="notification"/>
                        <context context="system_sound"/>
                    </device>
                </group>
            </volumeGroups>
        </zone>
    </zones>
</carAudioConfiguration>
```

我简单说下解析过程，先找name和isPrimary，在CarAudioZone中isPrimary只能有一个，如果是isPrimary则id是PRIMARY_AUDIO_ZONE ，否则是mNextSecondaryZoneId+1，关于除了primary的id的计算挺有意思。

```js
    private int getNextSecondaryZoneId() {
        int zoneId = mNextSecondaryZoneId;
        mNextSecondaryZoneId += 1;
        return zoneId;
    }
```

看到源码mNextSecondaryZoneId在初始化的时候，已经是1了，这里加1就变成了2，但虽然计算了，但返回的还是上次的值，也就是1，说白了就是primary是0，剩下累加1，有点意思。根据zone的标签我们知道了最终会创建多少个CarAudioZone，也就是最终返回的List< CarAudioZone>的size大小，我们继续再看具体的CarAudioZone里面有什么，首先是mVolumeGroups，CarAudioZone中会有一个mVolumeGroups的集合，而每个CarVolumeGroup都有什么呢？

```java
    CarVolumeGroup(Context context, int zoneId, int id) {
        mContentResolver = context.getContentResolver();
        mZoneId = zoneId;
        mId = id;
        mStoredGainIndex = Settings.Global.getInt(mContentResolver,
                CarAudioService.getVolumeSettingsKeyForGroup(mZoneId, mId), -1);
    }

```

mZoneId 我们知道就是之前分析的那个zoneId，mId就是我们我们每次mVolumeGroups.add的时候会传入一个从0开始累加的一个数，也就可以理解为list的索引，mStoredGainIndex数据库存存储的值。我们继续，group下就是device了，接下来就是根据device找的busNumber，busNumber之前也说过了，拿到busNumber后，解析context，有个map关系，根据context可以找到contextNumber

```java
    static {
        CONTEXT_NAME_MAP = new HashMap<>();
        CONTEXT_NAME_MAP.put("music", ContextNumber.MUSIC);
        CONTEXT_NAME_MAP.put("navigation", ContextNumber.NAVIGATION);
        CONTEXT_NAME_MAP.put("voice_command", ContextNumber.VOICE_COMMAND);
        CONTEXT_NAME_MAP.put("call_ring", ContextNumber.CALL_RING);
        CONTEXT_NAME_MAP.put("call", ContextNumber.CALL);
        CONTEXT_NAME_MAP.put("alarm", ContextNumber.ALARM);
        CONTEXT_NAME_MAP.put("notification", ContextNumber.NOTIFICATION);
        CONTEXT_NAME_MAP.put("system_sound", ContextNumber.SYSTEM_SOUND);
    }
```

有了busNumber，还可以找CarAudioDeviceInfo即mBusToCarAudioDeviceInfo.get(busNumber)，mBusToCarAudioDeviceInfo还记得刚才构建CarAudioDeviceInfo的之后我们创建了CarAudioZonesHelper传入的。这样拿到了busNumber、contextNumber和CarAudioDeviceInfo我们就可以做CarVolumeGroup的bind了

```java
    void bind(int contextNumber, int busNumber, CarAudioDeviceInfo info) {
        if (mBusToCarAudioDeviceInfo.size() == 0) {
            mStepSize = info.getAudioGain().stepValue();
        } else {
            Preconditions.checkArgument(
                    info.getAudioGain().stepValue() == mStepSize,
                    "Gain controls within one group must have same step value");
        }

        mContextToBus.put(contextNumber, busNumber);
        mBusToCarAudioDeviceInfo.put(busNumber, info);

        if (info.getDefaultGain() > mDefaultGain) {

            mDefaultGain = info.getDefaultGain();
        }
        if (info.getMaxGain() > mMaxGain) {
            mMaxGain = info.getMaxGain();
        }
        if (info.getMinGain() < mMinGain) {
            mMinGain = info.getMinGain();
        }
        if (mStoredGainIndex < getMinGainIndex() || mStoredGainIndex > getMaxGainIndex()) {

            mCurrentGainIndex = getIndexForGain(mDefaultGain);
        } else {

            mCurrentGainIndex = mStoredGainIndex;
        }
    }
```

因为group下所有音量都是一个步长，所以步长只赋值一次。mContextToBus把contextNumber和 busNumber存入map，mBusToCarAudioDeviceInfo则是把busNumber和info又重新存了一下，一个device下不管多少个context，volume对应的都是一次赋值。max min 以及current volume都是如此。
**简单总结每个group下的所有音量的步长都是一样的，每个group下device下的所有context的最大、最小、默认以及当前音量都是一样的。这有一个小问题要注意就是这个步长是以第一个device的步长为准，如果我们group下很多device，每个device的步长又不一样，那么就以第一device的步长为准**
到此音量就结束了，还有一个display的标签，刚才没有分析的mPortIds，其实就是通过解析这个display标签下的port然后存入mPortIds的集和中的，mPortIds除了判断重复好像也没啥大用。然后根据portId创建了一个DisplayAddress.Physical physicalDisplayAddress，然后加入到这个 private final List

今天就先分析到这里，从CarAudioService到解析构造CarVolumeGroup的过程，我们发现其实在CarAudio中的声音其实是根据group下的device下的context来区分的，一个device下的所有context的音量是一样的。明天继续分析CarZonesAudioFocus~
