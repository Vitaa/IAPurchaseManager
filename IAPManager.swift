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
    @objc public static let shared = IAPManager()
    
    override init() {
        super.init()
        
        restorePurchasedItems()
        
        SKPaymentQueue.default().add(self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(IAPManager.savePurchasedItems), name: UIApplication.didEnterBackgroundNotification, object: nil)
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: nil) { _ in
            SKPaymentQueue.default().remove(self)
        }
        
    }
    
    public func canMakePayments() -> Bool {
        if SKPaymentQueue.canMakePayments() {
            // check connection
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
    
    public func loadProducts(productIds: Array<String>, completion:@escaping LoadProductsCompletionBlock) {
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
        } else {
            let request = SKProductsRequest(productIdentifiers: Set(remainingIds))
            request.delegate = self
            loadProductsRequests.append(LoadProductsRequestInfo(request: request, completion: completion))
            request.start()
        }
    }
    
    public func purchaseProduct(productId: String, completion: @escaping PurchaseProductCompletionBlock) {
        if !canMakePayments() {
            let error = NSError(domain: "inapppurchase", code: 0, userInfo: [NSLocalizedDescriptionKey: "In App Purchasing is unavailable"])
            completion(error)
        } else {
            loadProducts(productIds: [productId]) { (products, error) -> Void in
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
    
    fileprivate func callLoadProductsCompletion(request: SKProductsRequest, responseProducts:Array<SKProduct>?, error: Error?) {
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
    
    fileprivate func callPurchaseProductCompletion(productId: String, error: Error?) {
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
        
        callLoadProductsCompletion(request: request, responseProducts: response.products, error: nil)
    }
    
    public func request(_ request: SKRequest, didFailWithError error: Error) {
        if let productRequest = request as? SKProductsRequest {
            callLoadProductsCompletion(request: productRequest, responseProducts: nil, error: error)
        }
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, didRevokeEntitlementsForProductIdentifiers productIdentifiers: [String]) {
        purchasedProductIds.removeAll { productIdentifiers.contains($0) }
        savePurchasedItems()
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
                
                callPurchaseProductCompletion(productId: productId, error: nil)
                queue.finishTransaction(transaction)
            case .failed:
                callPurchaseProductCompletion(productId: productId, error: transaction.error)
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

extension IAPManager { // Store file management
    
    func purchasedItemsURL() -> URL? {
        guard let documentsDirectory = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).first else { return nil }
        return URL(fileURLWithPath: documentsDirectory).appendingPathComponent("purchased.plist")
    }
    
    func restorePurchasedItems()  {
        do {
            guard let fileURL = purchasedItemsURL() else { return }
            let fileData = try Data(contentsOf: fileURL)
            if let items = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSArray.self, from: fileData) {
                for item in items {
                    guard let itemString = item as? String,
                          itemString.count <= 100 // App Store Connect limits iAP IDs to 100 chars
                        else { continue }
                    purchasedProductIds.append(itemString)
                }
            }
        } catch {
            // Ignore file does not exist errors
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                return
            }
            print("Failed to load saved purchased items: \(error)")
        }
    }
    
    @objc func savePurchasedItems() {
        guard let fileURL = purchasedItemsURL() else { return }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: purchasedProductIds, requiringSecureCoding: true)
            try data.write(to: fileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Failed to save purchased items: \(error)")
        }
    }
}
