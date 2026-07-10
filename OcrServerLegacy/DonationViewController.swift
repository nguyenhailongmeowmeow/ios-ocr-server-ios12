//
//  DonationViewController.swift
//  OcrServer (iOS 12 Legacy)
//
//  In-app purchase using StoreKit 1 (SKPaymentQueue).
//

import UIKit
import StoreKit

class DonationViewController: UIViewController, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    private let productId = "site.riddleling.app.OcrServer.iap.coffee"
    private var product: SKProduct?
    private var buyButton: UIButton!
    private var isBuying = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = NSLocalizedString("Donation", comment: "")
        view.backgroundColor = .white
        
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        }
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(dismissSelf)
        )
        
        setupUI()
        loadProduct()
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
        
        // Description
        let descLabel = UILabel()
        descLabel.text = "OCR Server provides all features for free to everyone. You can support this project by offering coffee."
        descLabel.font = UIFont.systemFont(ofSize: 16)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)
        
        // Coffee icon
        let iconLabel = UILabel()
        iconLabel.text = "☕"
        iconLabel.font = UIFont.systemFont(ofSize: 80)
        iconLabel.textAlignment = .center
        stack.addArrangedSubview(iconLabel)
        
        // One-time donation label
        let typeLabel = UILabel()
        typeLabel.text = "One-time donation"
        typeLabel.font = UIFont.systemFont(ofSize: 16)
        typeLabel.textAlignment = .center
        stack.addArrangedSubview(typeLabel)
        
        // Buy button
        buyButton = UIButton(type: .system)
        buyButton.setTitle("Loading...", for: .normal)
        buyButton.setTitleColor(.white, for: .normal)
        buyButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        buyButton.backgroundColor = .gray
        buyButton.layer.cornerRadius = 8
        buyButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        buyButton.isEnabled = false
        buyButton.addTarget(self, action: #selector(buyTapped), for: .touchUpInside)
        stack.addArrangedSubview(buyButton)
    }
    
    // MARK: - StoreKit 1
    
    private func loadProduct() {
        let request = SKProductsRequest(productIdentifiers: [productId])
        request.delegate = self
        request.start()
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let product = response.products.first {
                self.product = product
                let formatter = NumberFormatter()
                formatter.numberStyle = .currency
                formatter.locale = product.priceLocale
                let priceStr = formatter.string(from: product.price) ?? "\(product.price)"
                self.buyButton.setTitle("☕ \(product.localizedTitle)（\(priceStr)）", for: .normal)
                self.buyButton.backgroundColor = .systemBlue
                self.buyButton.isEnabled = true
            } else {
                self.buyButton.setTitle("Product not available", for: .normal)
            }
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.buyButton.setTitle("Failed to load", for: .normal)
        }
    }
    
    @objc private func buyTapped() {
        guard let product = product, !isBuying else { return }
        isBuying = true
        buyButton.isEnabled = false
        buyButton.backgroundColor = .gray
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    // MARK: - SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                SKPaymentQueue.default().finishTransaction(transaction)
                DispatchQueue.main.async { [weak self] in
                    self?.isBuying = false
                    self?.buyButton.isEnabled = true
                    self?.buyButton.backgroundColor = .systemBlue
                    self?.showThankYou()
                }
                
            case .failed:
                SKPaymentQueue.default().finishTransaction(transaction)
                DispatchQueue.main.async { [weak self] in
                    self?.isBuying = false
                    self?.buyButton.isEnabled = true
                    self?.buyButton.backgroundColor = .systemBlue
                }
                
            case .restored:
                SKPaymentQueue.default().finishTransaction(transaction)
                
            case .deferred, .purchasing:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    private func showThankYou() {
        let alert = UIAlertController(
            title: "Thank you!",
            message: NSLocalizedString("Thanks for buying me a coffee! I really appreciate your support.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
