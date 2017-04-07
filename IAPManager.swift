//
//  IAPManager.swift
//
//  Created by vitaa on 24/04/15.
//  Copyright (c) 2015 Vitaa. All rights reserved.
//

import Foundation
import StoreKit

public typealias RestoreTransactionsCompletionBlock = (Error?) -> Void
public typealias LoadProductsCompletionBlock = (Array<SKProduct>?, Error?) -> Void
public typealias PurchaseProductCompletionBlock = (Error?) -> Void
public typealias LoadProductsRequestInfo = (request: SKProductsRequest, completion: LoadProductsCompletionBlock)
public typealias PurchaseProductRequestInfo = (productId: String, completion: PurchaseProductCompletionBlock)

public class IAPManager: NSObject {
    public static let sharedManager = IAPManager()
    
    override init() {
        super.init()
        
        restorePurchasedItems()
        
        SKPaymentQueue.default().add(self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(IAPManager.savePurchasedItems), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    public func canMakePayments() -> Bool {
        if SKPaymentQueue.canMakePayments() {
            let hostname = "appstore.com"
            let hostinfo = gethostbyname(hostname)
            return hostinfo != nil
        }
        return false
    }
    
    public func isProductPurchased(productId: String) -> Bool {
        return purchasedProductIds.contains(productId)
    }
    
    public func restoreCompletedTransactions(completion: @escaping RestoreTransactionsCompletionBlock) {
        restoreTransactionsCompletionBlock = completion
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    public func loadProductsWithIds(productIds: Array<String>, completion:@escaping LoadProductsCompletionBlock) {
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
    
    public func purchaseProductWithId(productId: String, completion: @escaping PurchaseProductCompletionBlock) {
        if !canMakePayments() {
            let error = NSError(domain: "inapppurchase", code: 0, userInfo: [NSLocalizedDescriptionKey: "In App Purchasing is unavailable"])
            completion(error)
        } else {
            loadProductsWithIds(productIds: [productId]) { (products, error) -> Void in
                if error != nil {
                    completion(error)
                } else {
                    if let product = products?.first {
                        self.purchaseProduct(product: product, completion: completion)
                    }
                }
            }
        }
    }
    
    public func purchaseProduct(product: SKProduct, completion: @escaping PurchaseProductCompletionBlock) {
        purchaseProductRequests.append(PurchaseProductRequestInfo(productId: product.productIdentifier, completion: completion))
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    func callLoadProductsCompletionForRequest(request: SKProductsRequest, responseProducts:Array<SKProduct>?, error: Error?) {
        DispatchQueue.main.async() {
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
    
    func callPurchaseProductCompletionForProduct(productId: String, error: Error?) {
        DispatchQueue.main.async() {
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
    
    var availableProducts = Dictionary<String, SKProduct>()
    var purchasedProductIds = Array<String>()
    var restoreTransactionsCompletionBlock: RestoreTransactionsCompletionBlock?
    var loadProductsRequests = Array<LoadProductsRequestInfo>()
    var purchaseProductRequests = Array<PurchaseProductRequestInfo>()
    
}

extension IAPManager: SKProductsRequestDelegate {
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        for product in response.products {
            availableProducts[product.productIdentifier] = product
        }
        
        callLoadProductsCompletionForRequest(request: request, responseProducts: response.products, error: nil)
    }
    
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        if let productRequest = request as? SKProductsRequest {
            callLoadProductsCompletionForRequest(request: productRequest, responseProducts: nil, error: error)
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
                callPurchaseProductCompletionForProduct(productId: productId, error: nil)
                queue.finishTransaction(transaction)
            case .failed:
                callPurchaseProductCompletionForProduct(productId: productId, error: transaction.error)
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
            completion(error)
        }
    }
}

extension IAPManager {
    
    func purchasedItemsFilePath() -> String {
        let documentsDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.cachesDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first!
        return  (NSURL(string: documentsDirectory)?.appendingPathComponent("purchased.plist")!.path)!
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
            try (data as NSData).write(toFile: purchasedItemsFilePath(), options: [.atomicWrite, .completeFileProtection])
        } catch let error1 as NSError {
            error = error1
            print("Failed to save purchased items: \(String(describing: error))")
        }
    }
}
