ab后台管理功能接口介绍
===================

ab管理接口
------------------

```bash	
#策略管理
* /ab_admin?action=policy_check
* /ab_admin?action=policy_set
* /ab_admin?action=policy_get
* /ab_admin?action=policy_del
* /ab_admin?action=policy_update
* /ab_admin?action=policy_list
* /ab_admin?action=policy_pageList

#策略组管理（用于多级分流）
* /ab_admin?action=policygroup_check
* /ab_admin?action=policygroup_set
* /ab_admin?action=policygroup_get
* /ab_admin?action=policygroup_del
* /ab_admin?action=policygroup_list
* /ab_admin?action=policygroup_adminSet
* /ab_admin?action=policygroup_pageList

#灰度服务管理
* /ab_admin?action= grayserver.set
* /ab_admin?action= grayserver.check
* /ab_admin?action= grayserver.del
* /ab_admin?action= grayserver.get
* /ab_admin?action= grayserver.update
* /ab_admin?action= grayserver.pageList


#运行时信息设置（其中runtime_set接受policyid和policygroupid参数，分别用于单级分流和多级分流）
* /ab_admin?action=runtime_get
* /ab_admin?action=runtime_set
* /ab_admin?action=runtime_del
* /ab_admin?action=runtime_list
* /ab_admin?action=runtime_pageList

```
* 1.检查策略是否合法                    
    * curl localhost:port/ab_admin?action=policy_check -d '{"divtype":"uidsuffix","divdata":[{"suffix":"1","upstream":"beta1"},{"suffix":"3","upstream":"beta2"},{"suffix":"5","upstream":"beta1"},{"suffix":"0","upstream":"beta3"}]}'
    * 接口说明:
        * action: 代表要执行的操作，检查策略接口为policy_check
        * 仅接受POST方法，POST数据为待检查策略的json字符串
        * 返回值：{"code":200,"desc":"success "}，系统中如果返回非200的code码，就认为是发生错误，desc为错误信息。
        * 错误返回值：{"code":50102,"desc":"parameter error for postData is not a json string"} 如果出错，返回错误码与对应错误信息，反馈给用户，其他接口同样。


* 2.向系统添加策略                    
    * curl localhost:port/ab_admin?action=policy_set -d '{"divtype":"uidsuffix","divdata":[{"suffix":"1","upstream":"beta1"},{"suffix":"3","upstream":"beta2"},{"suffix":"5","upstream":"beta1"},{"suffix":"0","upstream":"beta3"}]}'`
  
    * 接口说明:    
        * action: 代表要执行的操作
        * 仅接受POST方法，POST数据为待检查策略的json字符串
        * 返回值：{"code":200,"desc":"success  the id of new policy is 20"}，策略添加成功，返回策略号policyid，样例中policyid为20
````  
   1.添加version分流策略

      curl server:port/ab_admin?action=policy_set
    
      提交报文：
      
        {
            "divtype": "version",
            "divdata": [
                {
                    "version": "2.1",
                    "upstream": "beta1"
                },
                {
                    "version": "2.2",
                    "upstream": "beta2"
                }
            ]
        }

   2.添加白名单策略
      curl server:port/ab_admin?action=policy_set

      提交报文：
            
          {
              "divtype": "uidappoint",
              "divdata": [
                  {
                      "uidset": [
                          1234,
                          5124,
                          653
                      ],
                      "upstream": "beta1"
                  },
                  {
                      "uidset": [
                          3214,
                          652,
                          145
                      ],
                      "upstream": "beta2"
                  }
              ]
          }

   3. 添加token分流策略
     
      curl server:port/ab_admin?action=policy_set
      
    提交报文
      
    {
        "divtype": "token",
        "divdata": [
            {
                "tokenset": [
                    "1",
                    "2",
                    "3"
                ],
                "upstream": "beta1"
            }
        ]
    }

    4.添加城市区域分流策略
      curl  server:port/ab_admin?action=policy_set

      提交报文
      
      {
          "divtype": "arg_city",
          "divdata": [
              {
                  "city": "BJ",
                  "upstream": "beta1"
              },
              {
                  "city": "SH",
                  "upstream": "beta2"
              },
              {
                  "city": "TJ",
                  "upstream": "beta1"
              },
              {
                  "city": "CQ",
                  "upstream": "beta3"
              }
          ]
      }
    
    
   

````

* 3.向系统修改策略
 * curl localhost:port/ab_admin?action=policy_update&policyid=20 -d '{"divtype":"uidsuffix","divdata":[{"suffix":"1","upstream":"beta1"},{"suffix":"3","upstream":"beta2"},{"suffix":"5","upstream":"beta1"},{"suffix":"0","upstream":"beta3"}]}'`
  
    * 接口说明:    
        * action: 代表要执行的操作
        * policyid: 要更新第policyid号策略
        * 仅接受POST方法，POST数据为待检查策略的json字符串
        * 返回值：{"code":200, "desc": "success  the id 20 of  policy is update20"}，策略修改成功


* 4.从系统读取策略                    
    * curl localhost:port/ab_admin?action=policy_get&policyid=20
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policyid: 获取第policyid号策略
        * 返回值：{"desc":"success ","code":200,"data":{"divdata":["1","beta1","3","beta2","5","beta1","0","beta3"],"divtype":"uidsuffix"}} 返回值中data部分是读取的策略数据，json格式。

* 5.从系统获取策略列表                  
    * curl localhost:port/ab_admin?action=policy_list
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 返回值：
        
        {
            "code": 200,
            "desc": "success ",
            "data": [
                {
                    "divtype": "uidsuffix",
                    "policyId": 9
                },
                {
                    "divtype": "arg_city",
                    "policyId": 10
                },
                {
                    "divtype": "uidsuffix",
                    "policyId": 6
                },
                {
                    "divtype": "arg_city",
                    "policyId": 2
                },
                {
                    "divtype": "iprange",
                    "policyId": 8
                },
                {
                    "divtype": "token",
                    "policyId": 0
                },
                {
                    "divtype": "uidsuffix",
                    "policyId": 9
                },
                {
                    "divtype": "uidsuffix",
                    "policyId": 3
                },
                {
                    "divtype": "iprange",
                    "policyId": 8
                },
                {
                    "divtype": "token",
                    "policyId": 0
                },
                {
                    "divtype": "version",
                    "policyId": 1
                },
                {
                    "divtype": "arg_city",
                    "policyId": 4
                }
            ]
        }
        
* 4.从系统刪除策略                    
    * curl localhost:port/ab_admin?action=policy_del&policyid=20
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policyid: 获取第policyid号策略
        * 返回值：{"desc":"success ","code":200} json格式。


* 6.检查策略组是否合法                    
    * curl  localhost:port/ab_admin?action=policygroup_check -d '{"1":{"divtype":"uidappoint","divdata":[{"uidset":[1234,5124,653],"upstream":"beta1"},{"uidset":[3214,652,145],"upstream":"beta2"}]},"2":{"divtype":"iprange","divdata":[{"range":{"start":1111,"end":2222},"upstream":"beta1"},{"range":{"start":3333,"end":4444},"upstream":"beta2"},{"range":{"start":7777,"end":8888},"upstream":"beta3"}]}}
  
    * 接口说明:    
        * action: 代表要执行的操作，检查策略接口为policygroup_check
        * 仅接受POST方法，POST数据为待检查策略的json字符串
        * 返回值：{"code":200,"desc":"success "}，系统中如果返回非200的code码，就认为是发生错误，desc为错误信息。
        * 错误返回值：{"code":50102,"desc":"parameter error for postData is not a json string"} 如果出错，返回错误码与对应错误信息，反馈给用户，其他接口同样。

*7.获取系统策略组列表
    * curl   localhost:port/ab_admin?action=policygroup_list
    * 接口说明:    
            * action: 代表要执行的操作
            * 返回值：
              {
                  "data": [
                      {
                          "groups": [
                              "9",
                              "10",
                              "11"
                          ],
                          "id": "2"
                      },
                      {
                          "groups": [
                              "3",
                              "4",
                              "5"
                          ],
                          "id": "0"
                      },
                      {
                          "groups": [
                              "6",
                              "7",
                              "8"
                          ],
                          "id": "1"
                      }
                  ],
                  "code": 200,
                  "desc": "success "
              }


* 8.向系统添加策略组                    
    * curl   localhost:port/ab_admin?action=policygroup_adminSet -d '{"policyids":[5,9,1]}'
  
    * 接口说明:    
        * action: 代表要执行的操作
        * 仅接受POST方法，POST数据为待检查策略的json字符串
          提交的报文
               {
                   "policyids": [
                       5,
                       9,
                       1
                   ]
               }  
        * 返回值：{"desc":"success ","code":200,"data":{"groupid":2,"group":[11,12]}}，策略组添加成功，返回策略组号groupid是2，组中包括两个策略，策略id分别是11和12.

* 9.从系统读取策略组                    
    * curl  localhost:port/ab_admin?action=policygroup_get&policygroupid=2
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policyid: 获取第policygroupid号策略组
        * 返回值：{"desc":"success ","code":200,"data":{"groupid":2,"group":["11","12"]}} 返回值以json格式返回该组策略中包括哪些策略。

* 10.从系统删除策略组                    
    * curl  localhost:port/ab_admin?action=policygroup_del&policygroupid=2
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policyid: 删除第policygroupid号策略组
        * 返回值：{"code":200,"desc":"success "}
        
 * 11.获取系统运行时策略列表         
     * curl  localhost:port/ab_admin?action=runtime_list
   
     * 接口说明:    
         * 参数：action: 代表要执行的操作
         * 返回值：
         {
             "desc": "success ",
             "code": 200,
             "data": [
                 {
                     "domain": "172.18.5.26",
                     "divtypes": [
                         "uidsuffix",
                         "arg_city",
                         "iprange"
                     ]
                 },
                 {
                     "domain": "localhost",
                     "divtypes": [
                         "uidsuffix",
                         "arg_city",
                         "iprange"
                     ]
                 },
                 {
                     "domain": "driverGateway-dev1.wsecar.com",
                     "divtypes": [
                         "token"
                     ]
                 }
             ]
         }
         
             

* 12.设置***策略***为系统的运行时策略，进行单级分流         
    * curl  localhost:port/ab_admin?action=runtime_set&policyid=22&hostname=api.weibo.cn
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policyid: 设置第policyid号策略为运行时策略
        * 参数：hostname：非常重要，向server api.weibo.cn绑定运行时信息，或向location /abc @server api.weibo.cn绑定运行时信息
        * 返回值：{"code":200,"desc":"success "}
        * 注意：设置运行时信息的动作会导致原来数据库中的运行时信息删除，不论本次设置是否成功

* 13.设置***策略组***为系统的运行时策略，进行多级分流
    * curl  localhost:port/ab_admin?action=runtime_set&policygroupid=4&hostname=www.wscar.com
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作
        * 参数：policygroupid: 设置第policygroupid号策略组   为运行时策略
        * 参数：hostname: 为host www.wscar.com设置运行时策略
        * 返回值：{"code":200,"desc":"success "}
        * 返回值：若发生错误，则有相关提示，比如某策略不存在。

        * 请注意：将 策略  或者 策略组 设置为运行时策略的接口是一样的，区别的方式在于参数是policyid还是policygroupid，所以要注意不要写错。
        * 请注意：设置运行时信息的动作会导致原来数据库中的运行时信息删除，不论本次设置是否成功


* 14.获取系统运行时信息 
    * curl  localhost:port/ab_admin?action=runtime_get&hostname=www.wscar.com
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，获取系统运行时信息runtime_get
        * 参数：hostname: 获取hostname主机的运行时信息
        * 系统未设置运行时信息时，返回值{"desc":"success ","code":200,"data":{"divsteps":0,"runtimegroup":{}}}
        * 系统设置运行时信息后，举例为：
           

```bash
        {
            "desc": "success ",
            "code": 200,
            "data": {
                "divsteps": 2,
                "runtimegroup": {
                    "second": {
                        "divModulename": "abtesting.diversion.iprange",
                        "divDataKey": "ab:test:policies:16:divdata",
                        "userInfoModulename": "abtesting.userinfo.ipParser"
                    },
                    "first": {
                        "divModulename": "abtesting.diversion.uidappoint",
                        "divDataKey": "ab:test:policies:15:divdata",
                        "userInfoModulename": "abtesting.userinfo.uidParser"
                    }
                }
            }
        }
        # divsteps表示几级分流
        # runtimegroup是分流信息，以first、second等作为下标，最多十级分流       
        # divModulename为运行时的分流模块名
        # userInfoModulename为运行时的用户信息提取模块名
        # divDataKey为运行时的分流策略名
```

* 15.删除系统运行时信息                   
    * curl  localhost:port/ab_admin?action=runtime_del&hostname=api.weibo.cn
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，删除系统运行时信息runtime_del
        * 返回值：{"code":200,"desc":"success "}
        
* 16.灰度服务设置 
    * curl  localhost:port/ab_admin?action=grayserver_set -d '[{"name":"abc","switch":"on"},{"name":"driver","switch":"off"}]'
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，新增灰度服务开关 grayserver_set
        * 系统设置灰度服务开关，返回值
        {
            "desc": "success ",
            "code": 200,
            "data": [
                "gray server abc",
                "gray server driver"
            ]
        }
        
* 17.灰度服务更新
    * curl  localhost:8080/ab_admin?action=grayserver_update&server_name=abc&switch=off
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，新增灰度服务开关 grayserver_update
        * 系统设置灰度服务开关，返回值
        {
            "desc": "success ",
            "code": 200,
            "data": "abc"
        }        

* 18.灰度服务删除
    * curl  localhost:8080/ab_admin?action=grayserver_del&server_name=driver
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，新增灰度服务开关 grayserver_del
        * 参数：server_name : 代表服务名
        * 灰度服务删除，返回值
        {
            "desc": "success ",
            "code": 200
        }  
        
* 19.灰度服务查看
             * curl  localhost:8080/ab_admin?action=grayserver_get&server_name=abc
           
             * 接口说明:    
                 * 参数：action: 代表要执行的操作，新增灰度服务开关 grayserver_get
                 * 参数：server_name : 代表服务名
                 * 灰度服务查看，返回值
                 {
                     "desc": "success ",
                     "code": 200,
                     "data": {
                         "switch": "on",
                         "name": "abc"
                     }
                 }
                 
* 20.灰度服务列表
    * curl  localhost:8080/ab_admin?action=grayserver_pageList&page=1&size=2
  
    * 接口说明:    
        * 参数：action: 代表要执行的操作，获取灰度服务列表 grayserver_pageList
        * 参数：page 页数
        * 参数：size 页码
        * 灰度服务列表，返回值
        {
            "code": 200,
            "data": [
                {
                    "name": "driver",
                    "switch": "off"
                },
                {
                    "name": "carlife",
                    "switch": "on"
                }
            ],
            "desc": "success "
        }

ab分流接口
------------------

* ab分流接口目前只能配置为 location /   
* 以***ab管理接口***小节中的第11条获取运行时信息为例，第一级是uidappoint白名单分流，第二级是iprange ip段分流方式

* curl localhost:port/ -H 'Host:www.wscar.com' -H 'X-Uid:30'
    * HOST字段是每个合法用户请求都有的，从HTTP 请求头中获取
    * 在匹配到virtual host和location后，分流功能通过location中设置的***hostkey***字段找到运行时信息，然后进行下一步的分流。
    * 因此location中的***$hostkey***字段是分流的基础，这里与ab管理功能中的设置运行时信息中的hostname参数一样

response格式
------------------

系统response采用json方式返回，resp包括返回码**code**、调用信息**desc**和调用结果**data**：

* 操作成功   
{***"code"***:200, ***"desc"***:"success", ***"data"***:["stable","beta1","beta2","beta3","beta4","beta5"]}

* 操作错误   
{***"code"***:500, ***"desc"***:"Invalid operation: get_upstream"}


