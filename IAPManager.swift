//
//  IAPManager.swift
//
//  Created by vitaa on 24/04/15.
//  Copyright (c) 2015 Vitaa. All rights reserved.
//

import Foundation
import StoreKit

typealias RestoreTransactionsCompletionBlock = NSError? -> Void
typealias LoadProductsCompletionBlock = (Array<SKProduct>?, NSError?) -> Void
typealias PurchaseProductCompletionBlock = (NSError?) -> Void
typealias LoadProductsRequestInfo = (request: SKProductsRequest, completion: LoadProductsCompletionBlock)
typealias PurchaseProductRequestInfo = (productId: String, completion: PurchaseProductCompletionBlock)

class IAPManager: NSObject {
    static let sharedManager = IAPManager()
    
    override init() {
        super.init()
        
        restorePurchasedItems()
        
        SKPaymentQueue.defaultQueue().addTransactionObserver(self)
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("savePurchasedItems"), name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    func canMakePayments() -> Bool {
        if SKPaymentQueue.canMakePayments() {
            // check connection
            let hostname = "appstore.com"
            let hostinfo = gethostbyname(hostname)
            return hostinfo != nil
        }
        return false
    }
    
    func isProductPurchased(productId: String) -> Bool {
        return contains(purchasedProductIds, productId)
    }
    
    func restoreCompletedTransactions(completion: RestoreTransactionsCompletionBlock) {
        restoreTransactionsCompletionBlock = completion
        SKPaymentQueue.defaultQueue().restoreCompletedTransactions()
    }
    
    func loadProductsWithIds(productIds: Array<String>, completion:LoadProductsCompletionBlock) {
        var loadedProducts = Array<SKProduct>()
        var remainingIds = Array<String>()
        
        for productId in productIds {
            if let product = availableProducts[productId] {
                loadedProducts.append(product)
            } else {
                remainingIds.append(productId)
            }
        }
        
        if count(remainingIds) == 0 {
            completion(loadedProducts, nil)
        }
        
        let request = SKProductsRequest(productIdentifiers: Set(remainingIds))
        request.delegate = self
        loadProductsRequests.append(LoadProductsRequestInfo(request: request, completion: completion))
        request.start()
    }
    
    func purchaseProductWithId(productId: String, completion: PurchaseProductCompletionBlock) {
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
    
    func purchaseProduct(product: SKProduct, completion: PurchaseProductCompletionBlock) {
        purchaseProductRequests.append(PurchaseProductRequestInfo(productId: product.productIdentifier, completion: completion))
        let payment = SKPayment(product: product)
        SKPaymentQueue.defaultQueue().addPayment(payment)
    }
    
    private func callLoadProductsCompletionForRequest(request: SKProductsRequest, responseProducts:Array<SKProduct>?, error: NSError?) {
        dispatch_async(dispatch_get_main_queue()) {
            for i in 0..<count(self.loadProductsRequests) {
                let requestInfo = self.loadProductsRequests[i]
                if requestInfo.request == request {
                    self.loadProductsRequests.removeAtIndex(i)
                    requestInfo.completion(responseProducts, error)
                    return
                }
            }
        }
    }
    
    private func callPurchaseProductCompletionForProduct(productId: String, error: NSError?) {
        dispatch_async(dispatch_get_main_queue()) {
            for i in 0..<count(self.purchaseProductRequests) {
                let requestInfo = self.purchaseProductRequests[i]
                if requestInfo.productId == productId {
                    self.purchaseProductRequests.removeAtIndex(i)
                    requestInfo.completion(error)
                    return
                }
            }
        }
    }
    
    private var availableProducts = Dictionary<String, SKProduct>()
    private var purchasedProductIds = Array<String>()
    private var restoreTransactionsCompletionBlock: RestoreTransactionsCompletionBlock?
    private var loadProductsRequests = Array<LoadProductsRequestInfo>()
    private var purchaseProductRequests = Array<PurchaseProductRequestInfo>()
    
}

extension IAPManager: SKProductsRequestDelegate {
    func productsRequest(request: SKProductsRequest!, didReceiveResponse response: SKProductsResponse!) {
        if let products = response.products as? [SKProduct] {
            for product in products {
                availableProducts[product.productIdentifier] = product
            }
            
            callLoadProductsCompletionForRequest(request, responseProducts: products, error: nil)
        }
    }
    
    func request(request: SKRequest!, didFailWithError error: NSError!) {
        if let productRequest = request as? SKProductsRequest {
            callLoadProductsCompletionForRequest(productRequest, responseProducts: nil, error: error)
        }
    }
}

extension IAPManager: SKPaymentTransactionObserver {
    
    func paymentQueue(queue: SKPaymentQueue!, updatedTransactions transactions: [AnyObject]!) {
        if let paymentTransactions = transactions as? [SKPaymentTransaction] {
            for transaction in paymentTransactions {
                let productId = transaction.payment.productIdentifier
                switch transaction.transactionState {
                case .Restored: fallthrough
                case .Purchased:
                    purchasedProductIds.append(productId)
                    savePurchasedItems()
                    
                    callPurchaseProductCompletionForProduct(productId, error: nil)
                    queue.finishTransaction(transaction)
                case .Failed:
                    callPurchaseProductCompletionForProduct(productId, error: transaction.error)
                    queue.finishTransaction(transaction)
                case .Purchasing:
                    println("Purchasing \(productId)...")
                default: break
                }
            }
        }
    }
    
    func paymentQueueRestoreCompletedTransactionsFinished(queue: SKPaymentQueue!) {
        if let completion = restoreTransactionsCompletionBlock {
            completion(nil)
        }
    }
    
    func paymentQueue(queue: SKPaymentQueue!, restoreCompletedTransactionsFailedWithError error: NSError!) {
        if let completion = restoreTransactionsCompletionBlock {
            completion(error)
        }
    }
}

extension IAPManager { // Store file managment
    
    func purchasedItemsFilePath() -> String {
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.CachesDirectory, NSSearchPathDomainMask.UserDomainMask, true).first! as! String
        return documentsDirectory.stringByAppendingPathComponent("purchased.plist")
    }
    
    func restorePurchasedItems()  {
        if let items = NSKeyedUnarchiver.unarchiveObjectWithFile(purchasedItemsFilePath()) as? Array<String> {
            purchasedProductIds.extend(items)
        }
    }
    
    func savePurchasedItems() {
        let data = NSKeyedArchiver.archivedDataWithRootObject(purchasedProductIds)
        var error: NSError?
        if !data.writeToFile(purchasedItemsFilePath(), options: .AtomicWrite | .DataWritingFileProtectionComplete, error: &error) {
            println("Failed to save purchased items: \(error)")
        }
    }
}