# IAPurchaseManager
Swift In-App Purchase Manager for iOS 

Easy-to-use a singleton class that supports non-renewable in-app purchases. 
It's super cool because</br>
1) it's written in Swift</br>
2) it uses blocks!

<h2>Making a purchase</h2>

If you want to make a purchase, all you need to do is to call a method:
```swift
  IAPManager.shared.purchaseProduct(productId: productId) { (error) -> Void in 
    if error == nil {
      // successful purchase!
    } else {
      // something wrong.. 
    }
}
```

You can call <b>purchaseProductWithId</b> without first loading products info because inside purchaseProductWithId it'll load it if needed. So just call <b>purchaseProductWithId</b> whenever you want to make a purchase. 

But if you need to get all products info, you can load it by calling:
```swift
  IAPManager.shared.loadProducts(productIds: []) { (products, error) in }
```

<h2>Check product was purchased</h2>

To check if a product was purchased, call (it returns Bool):
```swift
  IAPManager.shared.isProductPurchased(productId)
```

<h2>Restore transactions</h2>

To restore transactions call:
```swift
  IAPManager.shared.restoreCompletedTransactions { (error) in }
```

<h2>Details</h2>
All completed transactions are saved to a file:
```swift
data.write(to: purchasedItemsURL(), options: [.atomicWrite, .completeFileProtection])
```

<h2>Setup</h2> 
Just drag <b>IAPManager.swift</b> to your project.

<b>or</b> using <a href="https://cocoapods.org">CocoaPods</a>
```
pod 'IAPurchaseManager'
```

If you are using Swift 2.x, then
```
pod 'IAPurchaseManager', '~> 0.0.2'
```
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
```
github "Vitaa/IAPurchaseManager"
```

</br>
</br>
If you want to add validation, keychain support or some other features, feel free to send me pull requests!
