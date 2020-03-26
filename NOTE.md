
### help code

- 有关发消息的代码参考 `github.com/robotn/gohook` 的 hook/darwin

### oc 中 调用 swift
 project settings:
 - Build Settings -> Swift Compiler -Language -> ...Version {Swift 4}
 - Build Settings -> Assets -> Embed Asset Pack... {yes}
 - Build Settings -> Packaging -> Defines Module {yes}
 - Build Settings -> Packaging -> Product Name {your product name}
 
 ### 在Finder里面copy过去，还是没权限怎么办？
 从Project列表拖过去，可能是copy会产生其他的东西，和原始剪切的不同。。。
 
 ### `回调函数函数内部不再享受 autoreleasepool效应`
 此时，NSObject的release也不能调用，会编译错误，解决办法是在写个 autorelasepool把 NSObject包起来

### 手柄开发指南
[Game Controller Programming Guide](https://developer.apple.com/library/archive/documentation/ServicesDiscovery/Conceptual/GameControllerPG/ReadingControllerInputs/ReadingControllerInputs.html#//apple_ref/doc/uid/TP40013276-CH3-SW9)
