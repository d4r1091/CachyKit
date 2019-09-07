//
//  A.swift
//  Cachy
//
//  Created by sadman samee on 9/4/19.
//  Copyright © 2019 sadman samee. All rights reserved.
//

import Foundation
import UIKit

public typealias CachyCallback = (Data, URL) -> Void
public typealias CachyImageCallback = (UIImage, URL) -> Void
public typealias CachyCallbackList = [CachyCallback]

open class CachyManager {
    static let shared: CachyManager = {
        let instance = CachyManager()
        return instance
    }()

    fileprivate var cache: NSCache<NSString, AnyObject>!
    fileprivate var fetchList: [String: CachyCallbackList] = [:]
    fileprivate var fetchListOperationQueue: DispatchQueue = DispatchQueue(label: "cachy.awesome.fetchlist_queue", attributes: DispatchQueue.Attributes.concurrent)
    // fileprivate var imageDecodeQueue: DispatchQueue = DispatchQueue(label: "cachy.awesome.decode_queue", attributes: DispatchQueue.Attributes.concurrent)
    fileprivate var sessionConfiguration: URLSessionConfiguration!
    fileprivate var sessionQueue: OperationQueue!
    fileprivate lazy var defaultSession: URLSession! = URLSession(configuration: self.sessionConfiguration, delegate: nil, delegateQueue: self.sessionQueue)

//    fileprivate var memoryCapacity: Int!
//    fileprivate var diskCapacity: Int!
//    var maxConcurrentOperationCount: Int!
//    fileprivate var timeoutIntervalForRequest: Double!
//    fileprivate var diskPath: String!

    func configure(memoryCapacity: Int = 30 * 1024 * 1024, diskCapacity: Int = 30 * 1024 * 1024, maxConcurrentOperationCount: Int = 10, timeoutIntervalForRequest: Double = 3, diskPath: String = "temp") {
        cache.totalCostLimit = memoryCapacity
        sessionQueue = OperationQueue()
        sessionQueue.maxConcurrentOperationCount = maxConcurrentOperationCount
        sessionQueue.name = "cachy.awesome.session"
        sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.requestCachePolicy = .useProtocolCachePolicy
        sessionConfiguration.timeoutIntervalForRequest = timeoutIntervalForRequest

        sessionConfiguration.urlCache = URLCache(memoryCapacity: memoryCapacity,
                                                 diskCapacity: diskCapacity,
                                                 diskPath: diskPath)
    }

    private init(memoryCapacity: Int = 30 * 1024 * 1024, diskCapacity: Int = 30 * 1024 * 1024, maxConcurrentOperationCount: Int = 10, timeoutIntervalForRequest: Double = 3, diskPath: String = "temp") {
        cache = NSCache()
        configure(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, maxConcurrentOperationCount: maxConcurrentOperationCount, timeoutIntervalForRequest: timeoutIntervalForRequest, diskPath: diskPath)
    }
}

extension CachyManager {
    fileprivate func readFetch(_ key: String) -> CachyCallbackList? {
        return fetchList[key]
    }

    fileprivate func addFetch(_ key: String, callback: @escaping CachyCallback) -> Bool {
        var skip = false
        let list = fetchList[key]
        if list != nil {
            skip = true
        }
        fetchListOperationQueue.sync(flags: .barrier, execute: {
            if var fList = list {
                fList.append(callback)
                self.fetchList[key] = fList
            } else {
                self.fetchList[key] = [callback]
            }
        })
        return skip
    }

    fileprivate func removeFetch(_ key: String) {
        _ = fetchListOperationQueue.sync(flags: .barrier) {
            self.fetchList.removeValue(forKey: key)
        }
    }

    fileprivate func clearFetch() {
        fetchListOperationQueue.async(flags: .barrier) {
            self.fetchList.removeAll()
        }
    }
}

extension CachyManager {
    public func clearCache() {
        cache.removeAllObjects()
        sessionConfiguration.urlCache?.removeAllCachedResponses()
    }
}

// MARK: - CachyLoader

open class Cachy: NSObject {
    var task: URLSessionTask?
    public override init() {
        super.init()
    }
}

extension Cachy {
    fileprivate func cacheKeyFromUrl(url: URL) -> String? {
        let path = url.absoluteString
        let cacheKey = path
        return cacheKey
    }

    fileprivate func imageFromFastCache(cacheKey: String) -> UIImage? {
        return CachyManager.shared.cache.object(forKey: cacheKey as NSString) as? UIImage
    }

    fileprivate func dataFromFastCache(cacheKey: String) -> Data? {
        return CachyManager.shared.cache.object(forKey: cacheKey as NSString) as? Data
    }

    public func load(urlRequest: URLRequest, isRefresh: Bool = false, callback: @escaping CachyCallback) {
        guard let url = urlRequest.url else {
            return
        }

        guard let fetchKey = self.cacheKeyFromUrl(url: url as URL) else {
            return
        }
        if !isRefresh {
            if let data = self.dataFromFastCache(cacheKey: fetchKey) {
                callback(data, url)
                return
            }
        }
        let cacheCallback = {
            (data: Data) -> Void in
            if let fetchList = CachyManager.shared.readFetch(fetchKey) {
                CachyManager.shared.removeFetch(fetchKey)
                DispatchQueue.main.async {
                    for f in fetchList {
                        f(data, url)
                    }
                }
            }
        }
        let skip = CachyManager.shared.addFetch(fetchKey, callback: callback)
        if skip {
            return
        }
        /// request
        let session = CachyManager.shared.defaultSession
        let request = URLRequest(url: url)
        task = session?.dataTask(with: request, completionHandler: { data, _, _ in
            //            if let error = error {
            //
            //            }
            guard let data = data else {
                return
            }
            CachyManager.shared.cache.setObject(data as NSData, forKey: fetchKey as NSString)
            cacheCallback(data)
        })
        task?.resume()
    }

    public func load(url: URL, isRefresh: Bool = false, callback: @escaping CachyCallback) {
        guard let fetchKey = self.cacheKeyFromUrl(url: url as URL) else {
            return
        }
        if !isRefresh {
            if let data = self.dataFromFastCache(cacheKey: fetchKey) {
                callback(data, url)
                return
            }
        }
        let cacheCallback = {
            (data: Data) -> Void in
            if let fetchList = CachyManager.shared.readFetch(fetchKey) {
                CachyManager.shared.removeFetch(fetchKey)
                DispatchQueue.main.async {
                    for f in fetchList {
                        f(data, url)
                    }
                }
            }
        }
        let skip = CachyManager.shared.addFetch(fetchKey, callback: callback)
        if skip {
            return
        }
        let session = CachyManager.shared.defaultSession
        let request = URLRequest(url: url)
        task = session?.dataTask(with: request, completionHandler: { data, _, _ in
//            if let error = error {
//
//            }
            guard let data = data else {
                return
            }
            CachyManager.shared.cache.setObject(data as NSData, forKey: fetchKey as NSString)
            cacheCallback(data)
        })
        task?.resume()
    }
}

extension Cachy {
    public func cancelTask() {
        guard let _task = self.task else {
            return
        }
        if _task.state == .running || _task.state == .running {
            _task.cancel()
        }
    }
}