# Openresty-Gray
## 基于OpenResty的基础开发灰度分流的工具，支持多级分流策略

## 一、基于开源项目ABTestingGateway
  1. 修复了其中的小bug,在其基础上对分流策略做了进一步拓展，也增加了后台管理的接口，可以通过界面操作去控制灰度分流，前端界面暂时不开源
  Window上使用ant工具构建 ,参考 build.xml文件, inux构建需要编写发布脚本，方式很多，可以用python,shell，这里就不提供了

  2.相关接口和部署文档在 ./doc  文件夹下面
  


## 二、感谢
  ABTestingGateway 的开源作者 参考的开源地址如下：https://github.com/CNSRE/ABTestingGateway
