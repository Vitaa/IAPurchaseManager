//
//  IAPManager.swift
//
//  Created by vitaa on 24/04/15.
//  Copyright (c) 2015 Vitaa. All rights reserved.
//

import Foundation
import StoreKit

public typealias RestoreTransactionsCompletionBlock = (NSError?) -> Void
public typealias LoadProductsCompletionBlock = (Array<SKProduct>?, NSError?) -> Void
public typealias PurchaseProductCompletionBlock = (NSError?) -> Void
public typealias LoadProductsRequestInfo = (request: SKProductsRequest, completion: LoadProductsCompletionBlock)
public typealias PurchaseProductRequestInfo = (productId: String, completion: PurchaseProductCompletionBlock)

open class IAPManager: NSObject {
  open static let sharedManager = IAPManager()
  
  override init() {
    super.init()
    
    restorePurchasedItems()
    
    SKPaymentQueue.default().add(self)
    
    NotificationCenter.default.addObserver(self, selector: #selector(IAPManager.savePurchasedItems), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
  }
  
  open func canMakePayments() -> Bool {
    if SKPaymentQueue.canMakePayments() {
      // check connection
      let hostname = "appstore.com"
      let hostinfo = gethostbyname(hostname)
      return hostinfo != nil
    }
    return false
  }
  
  open func isProductPurchased(_ productId: String) -> Bool {
    return purchasedProductIds.contains(productId)
  }
  
  open func restoreCompletedTransactions(_ completion: @escaping RestoreTransactionsCompletionBlock) {
    restoreTransactionsCompletionBlock = completion
    SKPaymentQueue.default().restoreCompletedTransactions()
  }
  
  open func loadProductsWithIds(_ productIds: Array<String>, completion:@escaping LoadProductsCompletionBlock) {
    var loadedProducts = Array<SKProduct>()
    var remainingIds = Array<String>()
    
    for productId in productIds {
      if let product = availableProducts[productId] {
        loadedProducts.append(product)
      } else {
        remainingIds.append(productId)
      }
    }
    
    if remainingIds.count == 0 {
      completion(loadedProducts, nil)
    }
    
    let request = SKProductsRequest(productIdentifiers: Set(remainingIds))
    request.delegate = self
    loadProductsRequests.append(LoadProductsRequestInfo(request: request, completion: completion))
    request.start()
  }
  
  open func purchaseProductWithId(_ productId: String, completion: @escaping PurchaseProductCompletionBlock) {
    if !canMakePayments() {
      let error = NSError(domain: "inapppurchase", code: 0, userInfo: [NSLocalizedDescriptionKey: "In App Purchasing is unavailable"])
      completion(error)
    } else {
      loadProductsWithIds([productId]) { (products, error) -> Void in
        if error != nil {
          completion(error)
        } else {
          if let product = products?.first {
            self.purchaseProduct(product, completion: completion)
          }
        }
      }
    }
  }
  
  open func purchaseProduct(_ product: SKProduct, completion: @escaping PurchaseProductCompletionBlock) {
    purchaseProductRequests.append(PurchaseProductRequestInfo(productId: product.productIdentifier, completion: completion))
    let payment = SKPayment(product: product)
    SKPaymentQueue.default().add(payment)
  }
  
  fileprivate func callLoadProductsCompletionForRequest(_ request: SKProductsRequest, responseProducts:Array<SKProduct>?, error: NSError?) {
    DispatchQueue.main.async {
      for i in 0..<self.loadProductsRequests.count {
        let requestInfo = self.loadProductsRequests[i]
        if requestInfo.request == request {
          self.loadProductsRequests.remove(at: i)
          requestInfo.completion(responseProducts, error)
          return
        }
      }
    }
  }
  
  fileprivate func callPurchaseProductCompletionForProduct(_ productId: String, error: NSError?) {
    DispatchQueue.main.async {
      for i in 0..<self.purchaseProductRequests.count {
        let requestInfo = self.purchaseProductRequests[i]
        if requestInfo.productId == productId {
          self.purchaseProductRequests.remove(at: i)
          requestInfo.completion(error)
          return
        }
      }
    }
  }
  
  fileprivate var availableProducts = Dictionary<String, SKProduct>()
  fileprivate var purchasedProductIds = Array<String>()
  fileprivate var restoreTransactionsCompletionBlock: RestoreTransactionsCompletionBlock?
  fileprivate var loadProductsRequests = Array<LoadProductsRequestInfo>()
  fileprivate var purchaseProductRequests = Array<PurchaseProductRequestInfo>()
  
}

extension IAPManager: SKProductsRequestDelegate {
  public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    for product in response.products {
      availableProducts[product.productIdentifier] = product
    }
    
    callLoadProductsCompletionForRequest(request, responseProducts: response.products, error: nil)
  }
  
  public func request(_ request: SKRequest, didFailWithError error: Error) {
    if let productRequest = request as? SKProductsRequest {
      callLoadProductsCompletionForRequest(productRequest, responseProducts: nil, error: error as NSError?)
    }
  }
}

extension IAPManager: SKPaymentTransactionObserver {
  
  public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    for transaction in transactions {
      let productId = transaction.payment.productIdentifier
      switch transaction.transactionState {
      case .restored: fallthrough
      case .purchased:
        purchasedProductIds.append(productId)
        savePurchasedItems()
        
        callPurchaseProductCompletionForProduct(productId, error: nil)
        queue.finishTransaction(transaction)
      case .failed:
        callPurchaseProductCompletionForProduct(productId, error: transaction.error as NSError?)
        queue.finishTransaction(transaction)
      case .purchasing:
        print("Purchasing \(productId)...")
      default: break
      }
    }
  }
  
  public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
    if let completion = restoreTransactionsCompletionBlock {
      completion(nil)
    }
  }
  
  public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
    if let completion = restoreTransactionsCompletionBlock {
      completion(error as NSError?)
    }
  }
}

extension IAPManager { // Store file managment
  
  func purchasedItemsFilePath() -> String {
    let documentsDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first!
    return  (URL(string: documentsDirectory)?.appendingPathComponent("purchased.plist").path)!
  }
  
  func restorePurchasedItems()  {
    if let items = NSKeyedUnarchiver.unarchiveObject(withFile: purchasedItemsFilePath()) as? Array<String> {
      purchasedProductIds.append(contentsOf: items)
    }
  }
  
  func savePurchasedItems() {
    let data = NSKeyedArchiver.archivedData(withRootObject: purchasedProductIds)
    var error: NSError?
    do {
      try data.write(to: URL(fileURLWithPath: purchasedItemsFilePath()), options: [.atomicWrite, .completeFileProtection])
    } catch let error1 as NSError {
      error = error1
      print("Failed to save purchased items: \(error)")
    }
  }
}
