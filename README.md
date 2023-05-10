三行代码自动部署SD到谷歌colab。

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/AI-skimos/3line-colab-sd/blob/master/all.ipynb)
```
from google.colab import drive
drive.mount('/content/drive')
!bash <(curl -sL https://raw.githubusercontent.com/AI-skimos/3line-colab-sd/master/all.sh)
```
![](main.png)
## 特性
* 挂载谷歌云盘安装(请确保你的云盘有足够空间)
* 全程安全下载, 避免网络及服务中断/错误造成的文件或repo损坏
* 一次成功后不需要重复安装, 再次运行会跳过安装步骤
* 安装脚本自动升级,无需手动更新安装代码
* 基于https://github.com/camenduru/stable-diffusion-webui-colab, 集成大量插件及客制化改动
* 绕开colab对SD的检查(避免警告)
