# IAPurchaseManager
Swift In-App Purchase Manager for iOS 

Easy-to-use a singleton class that supports non-renewable in-app purchases. 
It's super cool because</br>
1) it's written in Swift</br>
2) it uses blocks!

If you want to <b>make a purchase</b>, all you need to do is to call a method:
```swift
  IAPManager.sharedManager.purchaseProductWithId(productId) { (error) -> Void in 
    if error == nil {
      // successful purchase!
    } else {
      // something wrong.. 
    }
}
```

Also you can <b>restore transactions</b>:
```swift
  IAPManager.sharedManager.restoreCompletedTransactions { (error) -> Void in }
```

or <b>load products info</b>:
```swift
  IAPManager.sharedManager.loadProductsWithIds(productIds) { (error) -> Void in }
```

All completed transactions are saved to a file:
```swift
data.writeToFile(purchasedItemsFilePath(), options: .AtomicWrite | .DataWritingFileProtectionComplete, error: &error)
```

</br>
</br>
If you want to add validation, keychain support or some other features, feel free to send me pull requests!
