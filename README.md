## Mac上针对特定程序，修改按键
- Maya：
    把z键映射成鼠标反键，优化对手写笔的操作
    
    
### help code

- 有关发消息的代码参考 github.com/robotn/gohook 的 hook/darwin

### oc 中 调用 swift
 project settings:
 - Build Settings -> Swift Compiler -Language -> ...Version {Swift 4}
 - Build Settings -> Assets -> Embed Asset Pack... {yes}
 - Build Settings -> Packaging -> Defines Module {yes}
 - Build Settings -> Packaging -> Product Name {your product name}
 
 ### 在Finder里面copy过去，还是没权限怎么办？
 从Project列表拖过去，可能是copy会产生其他的东西，和原始剪切的不同。。。