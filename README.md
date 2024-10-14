# Ok-ios-sdk (Swift Package Manager)
## tl;dr
Я сделал форк официальный либы для подключения ее с помощью SPM. Для описания работы SDK идите в официальную [репу](https://github.com/odnoklassniki/ok-ios-sdk).
Do you speak english m#$@%!!r: this is fork of ok-ios-sdk without unnecessary files working on Swift Package manager.
## Installation
### As part of project
Select Xcode menu `File > Swift Packages > Add Package Dependency` and paste repository URL.
```
https://github.com/hedump/Ok-ios-sdk
```
### Package inside another one
Add package in `dependencies` of your Package.swift
```swift
let package = Package(
    ...,
    dependencies: [
        .package(url: "https://github.com/hedump/Ok-ios-sdk", .exact("2.1.0"))
        ...
    ],
    targets: [
        .target(
            name: "MyPackage",
            dependencies: [
                "Ok-ios-sdk",
                ...
            ]
        ),
        ...
    ]
)
```
#### My manifest
I'm not gonna change or delete anything in this fork. Use it as it is.
## License
sdk maybe on original fork there is one
