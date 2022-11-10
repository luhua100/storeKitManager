//
//  LHPurchargeManager.swift
//  PurchargeManager
//
//  Created by zyfMac on 2022/6/2.
//

import UIKit
import StoreKit

#if DEBUG
let checkURL = "https://sandbox.itunes.apple.com/verifyReceipt"
#else
let checkURL = "https://buy.itunes.apple.com/verifyReceipt"
#endif

public protocol SkProductBuyInDelegate : NSObjectProtocol {
  
    //MARK: - 代理：系统错误
    func IAPToolSysWrong()
    //MARK: - 代理：已刷新可购买商品
    func IAPToolGotProducts(_ products : [SKProduct])
    //MARK: - 代理：购买成功 productID 商品ID
    func IAPToolBoughtProductSuccessedWithProductID(_ productID : String , _ infoDic : [String:Any]?)
    //MARK: - 代理：取消购买 productID 的商品ID
    func IAPToolCanceldWithProductID(_ productID : String)
    //MARK: - 代理：购买成功，开始验证购买 productID 商品ID
    func IAPToolBeginCheckingdWithProductID(_ productID : String)
    //MARK: - 代理：重复验证 的商品ID
    func IAPToolCheckRedundantWithProductID(_ productID : String)
    //MARK: - 代理：验证失败 商品ID
    func IAPToolCheckFailedWithProductID(_ productID : String , _ infoDic : Data)
    //MARK: - 代理：恢复了已购买的商品（永久性商品）
    func IAPToolRestoredProductID(_ productID : String)
    //MARK: - 代理： 验证购买凭据
    func localVerifyReceipt(_ receipt : String)
}

//typealias BoolBlock = (_ successed : Bool , _ result : Bool)->()
//
//typealias DicBlock = (_ successed : Bool , _ result : Dictionary<String,Any>)->()

public class LHPurchargeManager: NSObject {
  public static let shareManager = LHPurchargeManager()
   
  public  weak var delegate : SkProductBuyInDelegate?
    
    //购买完后是否在iOS端向服务器验证一次,默认为YES
    var CheckAfterPay : Bool = true
    
  public  var productDict : NSMutableDictionary?
    
  
    private  override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    //询问苹果的服务器能够销售哪些商品
    public  func requestProducts(_ products : [String]){
        let set = NSSet.init(array: products)
        //"异步"询问苹果能否销售
        let request = SKProductsRequest.init(productIdentifiers: set as! Set<String>)
        request.delegate = self
        //启动请求
        request.start()
    }
    //用户决定购买商品
    public func buyProduct(_ productID : String) {
        let product = productDict?[productID]
        // 要购买产品(店员给用户开了个小票)
        let payment = SKPayment.init(product: product as! SKProduct)
        // 去收银台排队，准备购买(异步网络)
        SKPaymentQueue.default().add(payment)
    }
    //恢复商品（仅限永久有效商品）
    public func restorePurchase() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    private func verifyPruchaseWithTransaction(_ transaction : SKPaymentTransaction){
        
        // 验证凭据，获取到苹果返回的交易凭据
        // appStoreReceiptURL iOS7.0增加的，购买交易完成后，会将凭据存放在该地址
        let receiptURL = Bundle.main.appStoreReceiptURL
        // 从沙盒中获取到购买凭据
        let receiptData = try? Data.init(contentsOf: receiptURL!)
        // 发送网络POST请求，对购买凭据进行验证
        let url = URL.init(string: checkURL)!
        var request = URLRequest.init(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20)
        request.httpMethod = "POST"
        // 在网络中传输数据，大多情况下是传输的字符串而不是二进制数据
        // 传输的是BASE64编码的字符串
        /**
         BASE64 常用的编码方案，通常用于数据传输，以及加密算法的基础算法，传输过程中能够保证数据传输的稳定性
         BASE64是可以编码和解码的
         */
        let encodeStr = receiptData?.base64EncodedString(options: .endLineWithLineFeed)
        let payload = "{\"receipt-data\" : \"\(encodeStr ?? "")\"}"
        let payloadData = payload.data(using: .utf8)
        request.httpBody = payloadData
        self.delegate?.localVerifyReceipt(encodeStr ?? "")
        //提交验证请求，并获得官方的验证JSON结果
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if data == nil {
                self.delegate?.IAPToolCheckFailedWithProductID(transaction.payment.productIdentifier, data ?? Data())
            }
            let dict = try? JSONSerialization.jsonObject(with: data ?? Data(), options: .fragmentsAllowed)
            if dict != nil {
                SKPaymentQueue.default().finishTransaction(transaction)
                self.delegate?.IAPToolBoughtProductSuccessedWithProductID(transaction.payment.productIdentifier, dict as? [String : Any])
            }else{
                self.delegate?.IAPToolCheckFailedWithProductID(transaction.payment.productIdentifier, data ?? Data())
            }
        }
        task.resume()
    }
    deinit {
        SKPaymentQueue.default().remove(self)
    }
}

extension LHPurchargeManager : SKProductsRequestDelegate,SKPaymentTransactionObserver {
    
    //MARK: - 获取询问结果，成功采取操作把商品加入可售商品字典里
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if productDict == nil {
            productDict  = NSMutableDictionary.init(capacity: response.products.count)
        }
        var productArray = [SKProduct]()
        for product in response.products {
            //填充商品字典
            productDict?.setObject(product, forKey: product.productIdentifier as NSCopying)
            productArray.append(product)
        }
        DispatchQueue.main.async {
            //通知代理
            self.delegate?.IAPToolGotProducts(productArray)
        }
        
    }
    //MARK: - 监测购买队列的变化
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        //处理结果
        for transaction in transactions {
            // 如果小票状态是购买完成
            if transaction.transactionState == .purchased {
                if self.CheckAfterPay == true {
                    //需要向苹果服务器验证一下
                    //通知代理
                    self.delegate?.IAPToolBeginCheckingdWithProductID(transaction.payment.productIdentifier)
                    // 验证购买凭据
                    self.verifyPruchaseWithTransaction(transaction)
                }else{
                    //需要向苹果服务器验证一下
                    //通知代理
                    self.delegate?.IAPToolBoughtProductSuccessedWithProductID(transaction.payment.productIdentifier, nil)
                }
            }else if transaction.transactionState == .restored {
                self.delegate?.IAPToolRestoredProductID(transaction.payment.productIdentifier)
                SKPaymentQueue.default().finishTransaction(transaction)
            }else if transaction.transactionState == .failed {
                SKPaymentQueue.default().finishTransaction(transaction)
                self.delegate?.IAPToolCanceldWithProductID(transaction.payment.productIdentifier)
            }else if transaction.transactionState == .purchasing {
                
            }else{
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        }
    }
}
