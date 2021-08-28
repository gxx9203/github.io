---
link: https://blog.csdn.net/longintchar/article/details/113796436
title: 网页转 markdown 的工具
description: 文章目录背景准备工作安装 clean-mark如何使用效果展示参考资料背景想把我在 CSDN 的博客备份下来，最好是 markdown 格式。在探索的过程中发现了一款工具——clean-mark它的仓库地址是：https://github.com/croqaz/clean-mark有人问为什么不保存成 html，而是要保存成 markdown 呢？clean-mark 在项目主页已经说得很清楚了：to save interesting articles offline, in a high
keywords: clean-mark
author: 车子 Chezi Csdn认证博客专家 Csdn认证企业博客 码龄8年 暂无认证
date: 2021-02-12T11:37:00.000Z
publisher: null
tags:
    - CSDN转载
    - Tools
stats: paragraph=47 sentences=22, words=168
---
### 文章目录

*
  - [背景](#-1)
  - [准备工作](#-20)
  - [安装 clean-mark](#-cleanmark-67)
  - [如何使用](#-75)
  - [效果展示](#-111)
  - [参考资料](#-119)

## 背景

想把我在 CSDN 的博客备份下来，最好是 markdown 格式。在探索的过程中发现了一款工具——clean-mark

它的仓库地址是：

https://github.com/croqaz/clean-mark

有人问为什么不保存成 html，而是要保存成 markdown 呢？

clean-mark 在项目主页已经说得很清楚了：

>

* to save interesting articles offline, in a highly readable text format
* it's easy to read on a tablet, or a Kindle (as it is, or exported to PDF)
* Markdown is easy to export into different formats
* for offline text analysis of multiple articles, using machine learning / AI

## 准备工作

要用 clean-mark 这个工具，需要安装 npm 和 nodejs

> NPM 的全称是 Node Package Manager，是随同 NodeJS 一起安装的包管理和分发工具，它很方便让 JavaScript 开发者下载、安装、上传以及管理已经安装的包。

```
sudo apt-get install npm
```

除了安装 npm，还需要安装 nodejs

```
sudo apt-get install nodejs-dev
```

我是Ubuntu 的环境，没有用上面的命令安装 nodejs，但是版本太低，需要升级

我搜到的方法是

```
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
```

查看版本：

```
node -v
npm -v
```

我升级后查看的结果是

```
$ node -v
v14.15.5
$ npm -v
6.14.11

```

## 安装 clean-mark

```
$ npm install clean-mark --global
```

## 如何使用

根据说明，可以指定下载的类型，可以选择的类型有：

HTML, TEXT and Markdown.

举例：

> $ clean-mark "http://some-website.com/fancy-article" -t html

也可以指定输出路径和文件名，比如：

> $ clean-mark "http://some-website.com/fancy-article" -o /tmp/article

咱们动手试试。比如我的一篇博客地址是

https://blog.csdn.net/longintchar/article/details/113074860

```
$ clean-mark "https://blog.csdn.net/u013490896/article/details/113075606"
```

运行后会显示

```
=>  Processing URL ...

> 113075606.md
=>  URL converted!

```

**注意：命令中的链接也可以没有两侧的引号**
当前目录下会多出来一个文件 `113075606.md`

## 效果展示

![](https://img-blog.csdnimg.cn/20210212193636205.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3UwMTM0OTA4OTY=,size_16,color_FFFFFF,t_70)

![](https://img-blog.csdnimg.cn/20210212193644665.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L3UwMTM0OTA4OTY=,size_16,color_FFFFFF,t_70)

## <a name="_119">;</a> 参考资料

[0] https://github.com/croqaz/clean-mark

[1] [ubuntu安装nodejs并升级到最新版本](https://www.centos.bz/2017/11/ubuntu%E5%AE%89%E8%A3%85nodejs%E5%B9%B6%E5%8D%87%E7%BA%A7%E5%88%B0%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC/)
