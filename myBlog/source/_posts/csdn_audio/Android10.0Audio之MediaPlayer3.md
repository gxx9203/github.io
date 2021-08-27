---
link: https://blog.csdn.net/l328873524/article/details/104158291
title: Android10.0Auidio之MediaPlayer （三）
description: 不知不觉就2020年了，不知不觉Android就到了10.0了，考虑了下后续还是基于10.0来继续分析吧。之前说过了MediaPlayer java层的一些API的逻辑。今天继续向下分析...
keywords: Android10.0Auidio之MediaPlayer （三）
author: 轻量级Lz Csdn认证博客专家 Csdn认证企业博客 码龄9年 暂无认证
date: 2020-03-23T15:55:00.000Z
publisher: null
tags:
    - CSDN转载
    - Audio
stats: paragraph=37 sentences=48, words=769
---
之前说过了MediaPlayer java层的到jni的故事，我们知道了jni是如何跟java层mediaplayer联系上的，包括mediaplayer的初始化，callback的调用等，今天在来简单聊下setDataSource。

MediaPlayer的setDataSource方法主要如下

setDataSource(FileDescriptor)

setDataSource(String)

setDataSource(Context, Uri)

setDataSource(FileDescriptor, long, long)

setDataSource(MediaDataSource)

这里我们就说下这个比较常用的吧setDataSource(String)。传递一个path下来，先看源码

```java
  public void setDataSource(String path)
            throws IOException, IllegalArgumentException, SecurityException, IllegalStateException {
        setDataSource(path, null, null);
    }
    @UnsupportedAppUsage
    private void setDataSource(String path, Map headers, List cookies)
            throws IOException, IllegalArgumentException, SecurityException, IllegalStateException
    {
        String[] keys = null;
        String[] values = null;

        if (headers != null) {
            keys = new String[headers.size()];
            values = new String[headers.size()];

            int i = 0;
            for (Map.Entry entry: headers.entrySet()) {
                keys[i] = entry.getKey();
                values[i] = entry.getValue();
                ++i;
            }
        }
        setDataSource(path, keys, values, cookies);
    }

    @UnsupportedAppUsage
    private void setDataSource(String path, String[] keys, String[] values,
            List cookies)
            throws IOException, IllegalArgumentException, SecurityException, IllegalStateException {
        final Uri uri = Uri.parse(path);
        final String scheme = uri.getScheme();
        if ("file".equals(scheme)) {
            path = uri.getPath();
        } else if (scheme != null) {
            // handle non-file sources
            nativeSetDataSource(
                MediaHTTPService.createHttpServiceBinderIfNecessary(path, cookies),
                path,
                keys,
                values);
            return;
        }

        final File file = new File(path);
        try (FileInputStream is = new FileInputStream(file)) {
            setDataSource(is.getFD());
        }
    }
```

我们发现调到jni的是 setDataSource(is.getFD());

```java
    public void setDataSource(FileDescriptor fd)
            throws IOException, IllegalArgumentException, IllegalStateException {
        // intentionally less than LONG_MAX
        setDataSource(fd, 0, 0x7ffffffffffffffL);
    }

    public void setDataSource(FileDescriptor fd, long offset, long length)
            throws IOException, IllegalArgumentException, IllegalStateException {
        _setDataSource(fd, offset, length);
    }

    private native void _setDataSource(FileDescriptor fd, long offset, long length)
            throws IOException, IllegalArgumentException, IllegalStateException;
```

兜兜转转，绕来绕去最终调到了native的_setDataSource，虽然setDataSource的每个方法最终调到native的方法不尽相同，但也大同小异。

我们知道，我们set一个path下来后，其实就是把对应的文件描述符传递了下来。继续分析

```cpp
static void
android_media_MediaPlayer_setDataSourceFD(JNIEnv *env, jobject thiz, jobject fileDescriptor, jlong offset, jlong length)
{
    sp mp = getMediaPlayer(env, thiz);
    if (mp == NULL ) {
        jniThrowException(env, "java/lang/IllegalStateException", NULL);
        return;
    }

    if (fileDescriptor == NULL) {
        jniThrowException(env, "java/lang/IllegalArgumentException", NULL);
        return;
    }
    int fd = jniGetFDFromFileDescriptor(env, fileDescriptor);
    ALOGV("setDataSourceFD: fd %d", fd);
  // 将mp的setDataSource的结果回调到java层
    process_media_player_call( env, thiz, mp->setDataSource(fd, offset, length), "java/io/IOException", "setDataSourceFD failed." );
}
```

将结果通过process_media_player_call回调到上层应用，

关于mp->setDataSource(fd, offset, length)的等下文再说，这里先说jni。那么setDataSource的结果是如何回调上去的呢？我们继续看process_media_player_call

```cpp
static void process_media_player_call(JNIEnv *env, jobject thiz, status_t opStatus, const char* exception, const char *message)
{
    if (exception == NULL) {  // Don't throw exception. Instead, send an event.

        if (opStatus != (status_t) OK) {
            sp mp = getMediaPlayer(env, thiz);

            if (mp != 0) mp->notify(MEDIA_ERROR, opStatus, 0);
        }
    } else {  // Throw exception!

        if ( opStatus == (status_t) INVALID_OPERATION ) {
            jniThrowException(env, "java/lang/IllegalStateException", NULL);
        } else if ( opStatus == (status_t) BAD_VALUE ) {
            jniThrowException(env, "java/lang/IllegalArgumentException", NULL);
        } else if ( opStatus == (status_t) PERMISSION_DENIED ) {
            jniThrowException(env, "java/lang/SecurityException", NULL);
        } else if ( opStatus != (status_t) OK ) {
            if (strlen(message) > 230) {
               // if the message is too long, don't bother displaying the status code
               jniThrowException( env, exception, message);
            } else {
               char msg[256];
                // append the status code to the message
               sprintf(msg, "%s: status=0x%X", message, opStatus);
               jniThrowException( env, exception, msg);
            }
        }
    }
}
```

```cpp
void JNIMediaPlayerListener::notify(int msg, int ext1, int ext2, const Parcel *obj)
{
    JNIEnv *env = AndroidRuntime::getJNIEnv();
    if (obj && obj->dataSize() > 0) {
        jobject jParcel = createJavaParcelObject(env);
        if (jParcel != NULL) {
            Parcel* nativeParcel = parcelForJavaObject(env, jParcel);
            nativeParcel->setData(obj->data(), obj->dataSize());
            //fields.post_event是不是很眼熟，就是上一篇我们说到postEventFromNative
            env->CallStaticVoidMethod(mClass, fields.post_event, mObject,
                    msg, ext1, ext2, jParcel);
            env->DeleteLocalRef(jParcel);
        }
    } else {
        env->CallStaticVoidMethod(mClass, fields.post_event, mObject,
                msg, ext1, ext2, NULL);
    }
    if (env->ExceptionCheck()) {
        ALOGW("An exception occurred while notifying an event.");
        LOGW_EX(env);
        env->ExceptionClear();
    }
}
```

我们发现最终通过postEventFromNative回调上来了，我们继续看下java层的postEventFromNative方法，代码有点长，我节选其中一段吧

```java
        if (mp.mEventHandler != null) {
            Message m = mp.mEventHandler.obtainMessage(what, arg1, arg2, obj);
            mp.mEventHandler.sendMessage(m);
        }
```

再看下handler是如何处理消息的，都是一些switch/case，这里说下回调上来的MEDIA_ERROR

```java
            case MEDIA_ERROR:
                Log.e(TAG, "Error (" + msg.arg1 + "," + msg.arg2 + ")");
                boolean error_was_handled = false;
                OnErrorListener onErrorListener = mOnErrorListener;
                if (onErrorListener != null) {
                    error_was_handled = onErrorListener.onError(mMediaPlayer, msg.arg1, msg.arg2);
                }
                {
                    mOnCompletionInternalListener.onCompletion(mMediaPlayer);
                    OnCompletionListener onCompletionListener = mOnCompletionListener;
                    if (onCompletionListener != null && ! error_was_handled) {
                        onCompletionListener.onCompletion(mMediaPlayer);
                    }
                }
                stayAwake(false);
                return;
```

代码不是很多，但是有几点需要注意：

1.我们发现最终通过onErrorListener 或者onCompletionListener回调上去，也就是说我们setOnErrorListener和setOnCompletionListener一定要在setDataSource之前完成，否则就收不到了callback

2.如果报错了，我们不想继续播放可以onError中return true，这样就不会触发onCompletionListener.onCompletion的回调了。

MediaPlayer的java层跟jni层的交互就差不多了，我们在调用java层的api时其实都是通过jni调到native的，native通过java的方法回调上来。

下一篇我们开始真正分下下native的mediaplayer。
