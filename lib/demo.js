(function () {
    if (typeof EthereumProvider === "undefined") {
        var callbackId = 0;
        var callbacks = {};

        var bridgeSend = function (data) {
            ReactNativeWebView.postMessage(JSON.stringify(data));
        }

        var history = window.history;
        var pushState = history.pushState;
        history.pushState = function (state) {
            setTimeout(function () {
                bridgeSend({
                    type: 'history-state-changed',
                    navState: { url: location.href, title: document.title }
                });
            }, 100);
            return pushState.apply(history, arguments);
        };

        function sendAPIrequest(permission, params) {
            var messageId = callbackId++;
            var params = params || {};

            bridgeSend({
                type: 'api-request',
                permission: permission,
                messageId: messageId,
                params: params
            });

            return new Promise(function (resolve, reject) {
                params['resolve'] = resolve;
                params['reject'] = reject;
                callbacks[messageId] = params;
            });
        }

        function qrCodeResponse(data, callback) {
            var result = data.data;
            var regex = new RegExp(callback.regex);
            if (!result) {
                if (callback.reject) {
                    callback.reject(new Error("Cancelled"));
                }
            }
            else if (regex.test(result)) {
                if (callback.resolve) {
                    callback.resolve(result);
                }
            } else {
                if (callback.reject) {
                    callback.reject(new Error("Doesn't match"));
                }
            }
        }

        function Unauthorized() {
            this.name = "Unauthorized";
            this.id = 4100;
            this.code = 4100;
            this.message = "The requested method and/or account has not been authorized by the user.";
        }
        Unauthorized.prototype = Object.create(Error.prototype);

        function UserRejectedRequest() {
            this.name = "UserRejectedRequest";
            this.id = 4001;
            this.code = 4001;
            this.message = "The user rejected the request.";
        }
        UserRejectedRequest.prototype = Object.create(Error.prototype);
        ReactNativeWebView.onMessage = function (message) {
            data = JSON.parse(message);
            var id = data.messageId;
            var callback = callbacks[id];

            if (callback) {
                if (data.type === "api-response") {
                    if (data.permission == 'qr-code') {
                        qrCodeResponse(data, callback);
                    } else if (data.isAllowed) {
                        if (data.permission == 'web3') {
                            window.statusAppcurrentAccountAddress = data.data[0];
                            window.ethereum.emit("accountsChanged", data.data);
                        }
                        callback.resolve(data.data);
                    } else {
                        callback.reject(new UserRejectedRequest());
                    }
                }
                else if (data.type === "web3-send-async-callback") {
                    if (callback.beta) {
                        if (data.error) {
                            if (data.error.code == 4100)
                                callback.reject(new Unauthorized());
                            else
                                callback.reject(data.error);
                        }
                        else {
                            callback.resolve(data.result.result);
                        }
                    }
                    else if (callback.results) {
                        callback.results.push(data.error || data.result);
                        if (callback.results.length == callback.num)
                            callback.callback(undefined, callback.results);
                    }
                    else {
                        callback.callback(data.error, data.result);
                    }
                }
            }
        };

        function web3Response(payload, result) {
            return {
                id: payload.id,
                jsonrpc: "2.0",
                result: result
            };
        }

        function getSyncResponse(payload) {
            if (payload.method == "eth_accounts" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
                return web3Response(payload, [window.statusAppcurrentAccountAddress])
            } else if (payload.method == "eth_coinbase" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
                return web3Response(payload, window.statusAppcurrentAccountAddress)
            } else if (payload.method == "net_version" || payload.method == "eth_chainId") {
                return web3Response(payload, window.statusAppNetworkId)
            } else if (payload.method == "eth_uninstallFilter") {
                return web3Response(payload, true);
            } else {
                return null;
            }
        }

        var StatusAPI = function () { };

        StatusAPI.prototype.getContactCode = function () {
            return sendAPIrequest('contact-code');
        };

        var EthereumProvider = function () { };

        EthereumProvider.prototype.isStatus = true;
        EthereumProvider.prototype.status = new StatusAPI();
        EthereumProvider.prototype.isConnected = function () { return true; };

        EthereumProvider.prototype._events = {};

        EthereumProvider.prototype.on = function (name, listener) {
            if (!this._events[name]) {
                this._events[name] = [];
            }
            this._events[name].push(listener);
        }

        EthereumProvider.prototype.removeListener = function (name, listenerToRemove) {
            if (!this._events[name]) {
                return
            }

            const filterListeners = (listener) => listener !== listenerToRemove;
            this._events[name] = this._events[name].filter(filterListeners);
        }

        EthereumProvider.prototype.emit = function (name, data) {
            if (!this._events[name]) {
                return
            }
            this._events[name].forEach(cb => cb(data));
        }
        EthereumProvider.prototype.enable = function () {
            if (window.statusAppDebug) { console.log("enable"); }
            return sendAPIrequest('web3');
        };

        EthereumProvider.prototype.scanQRCode = function (regex) {
            return sendAPIrequest('qr-code', { regex: regex });
        };

        EthereumProvider.prototype.request = function (requestArguments) {
            if (window.statusAppDebug) { console.log("request: " + JSON.stringify(requestArguments)); }
            if (!requestArguments) {
                return new Error('Request is not valid.');
            }
            var method = requestArguments.method;

            if (!method) {
                return new Error('Request is not valid.');
            }

            //Support for legacy send method
            if (typeof method !== 'string') {
                return this.sendSync(method);
            }

            if (method == 'eth_requestAccounts') {
                return sendAPIrequest('web3');
            }

            var messageId = callbackId++;
            var payload = {
                id: messageId,
                jsonrpc: "2.0",
                method: method,
                params: requestArguments.params
            };

            bridgeSend({
                type: 'web3-send-async-read-only',
                messageId: messageId,
                payload: payload
            });

            return new Promise(function (resolve, reject) {
                callbacks[messageId] = {
                    beta: true,
                    resolve: resolve,
                    reject: reject
                };
            });
        };

        // (DEPRECATED) Support for legacy send method
        EthereumProvider.prototype.send = function (method, params = []) {
            if (window.statusAppDebug) { console.log("send (legacy): " + method); }
            return this.request({ method: method, params: params });
        }

        // (DEPRECATED) Support for legacy sendSync method
        EthereumProvider.prototype.sendSync = function (payload) {
            if (window.statusAppDebug) { console.log("sendSync (legacy)" + JSON.stringify(payload)); }
            if (payload.method == "eth_uninstallFilter") {
                this.sendAsync(payload, function (res, err) { })
            }
            var syncResponse = getSyncResponse(payload);
            if (syncResponse) {
                return syncResponse;
            } else {
                return web3Response(payload, null);
            }
        };

        // (DEPRECATED) Support for legacy sendAsync method
        EthereumProvider.prototype.sendAsync = function (payload, callback) {
            if (window.statusAppDebug) { console.log("sendAsync (legacy)" + JSON.stringify(payload)); }
            if (!payload) {
                return new Error('Request is not valid.');
            }
            if (payload.method == 'eth_requestAccounts') {
                return sendAPIrequest('web3');
            }
            var syncResponse = getSyncResponse(payload);
            if (syncResponse && callback) {
                callback(null, syncResponse);
            }
            else {
                var messageId = callbackId++;

                if (Array.isArray(payload)) {
                    callbacks[messageId] = {
                        num: payload.length,
                        results: [],
                        callback: callback
                    };
                    for (var i in payload) {
                        bridgeSend({
                            type: 'web3-send-async-read-only',
                            messageId: messageId,
                            payload: payload[i]
                        });
                    }
                }
                else {
                    callbacks[messageId] = { callback: callback };
                    bridgeSend({
                        type: 'web3-send-async-read-only',
                        messageId: messageId,
                        payload: payload
                    });
                }
            }
        };
    }

    window.ethereum = new EthereumProvider();
})();


/**
onMessageReceived: (JavascriptMessage message) {
    Map _msg = convert.jsonDecode(message.message);
    String type = _msg['type'];
    String msg;
    print(message.message);
    if (type == 'api-request') {
      _msg["isAllowed"] = true;
      _msg["type"] = "api-response";
      _msg["data"] = ["0xf93B52193658335DBfe7b9138a0Da4CCEb6aF466"];
      msg = convert.jsonEncode(_msg);
    } else if (type == 'web3-send-async-read-only') {
      Map payload = _msg['payload'];
      String method = payload['method'];
      _msg["type"] = "web3-send-async-callback";
      _msg["result"] = {
        "jsonrpc": payload['jsonrpc'],
        "id": payload['id'],
      };
      switch (method) {
        case "eth_chainId":
          {
            _msg["result"]["result"] = "0x61";
          }
          break;
      }

      msg = convert.jsonEncode(_msg);
    }
    _controller.evaluateJavascript('''
        FlutterChannel.onMessage('$msg')
      ''');
  },
);
 */

 /**
ethereum
    .request({
        method: 'eth_sendTransaction', params: [
            {
                from: "0x35395900ab1335532d17d8ba362ebe45bacbc6f8",
                to: '0xf93B52193658335DBfe7b9138a0Da4CCEb6aF466',
                value: '0x429d069189e0000',
                gas: "0x76c0",
                gasPrice: "0x9184e72a000",
            }
        ]
    })
    .then(data => {
        console.log(data);
        console.log(JSON.stringify(data));
    })
    .catch(error => {
        if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
        } else {
            console.error(error);
        }
    });
    // "0x2f3e4d9e82544a66dda5851218940ff3aa399c75ef4df7ed8e3207543367fc6c"

// 测试网查询 https://ropsten.etherscan.io/tx/0xa29a67785d739daa723ca626d4002da9572dbe704f9075b4765d66e2df97beb7   
*/

/**
 申请加密公钥
ethereum
        .request({ method: 'eth_getEncryptionPublicKey', params: ["0x35395900ab1335532d17d8ba362ebe45bacbc6f8"], })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });

 // 返回值 MoouigwUlqpTk/cMMTZ627d7vK77KvzTIbnFi46CFAo=
* 
 */

 /**
  * 解密请求
  * ethereum
        .request({ 
            method: 'eth_decrypt', 
            params: [
            "0x7b2276657273696f6e223a227832353531392d7873616c736132302d706f6c7931333035222c226e6f6e6365223a22364d505169514a746a54546a6b50726731576a6c446348785630363359484234222c22657068656d5075626c69634b6579223a226d6c4a6e54395754337a71714b37736a624b6d4d664b5762337a665336594569365070616f39752b6956493d222c2263697068657274657874223a227a374d4f6968786543716f447a343168382b4c6e4266327074616a2f6b51335a4754773d227d",
            "0x35395900ab1335532d17d8ba362ebe45bacbc6f8"],
         })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });
  */

  /**
   * 获取 eth_chainId
   * ethereum
        .request({ method: 'eth_chainId' })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });
        // "0x3"
   */

/**
 * ethereum
        .request({ method: 'net_version' })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });
        // 3
 */

 /**
  * 对构建交易 - 请求签名 （地址、构建交易的数据）
  * ethereum
        .request({ 
            method: 'eth_sign', 
            params: [
                "0x35395900ab1335532d17d8ba362ebe45bacbc6f8",
                 "0xbc5a151e5d38eac7a5424ec5c4de1ef190dd6d2053dfaf44749cfe1ff20c427e"
                ],
                 })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });

        // 返回签名： "0xf346116c379efa562c2da6103020ffd5b831742f14d291674b7cbc55151385e625f623d1a91ca35ca130867e5f57cff7aa232463aa7b2f66e5518f42ed55e8dc1c"
  */

  
/**
 * 返回最新块的编号
 * eth_blockNumber
 * ethereum
        .request({ method: 'eth_blockNumber', params: [], })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });
        // 0x9b8e7f
 * 
 */

 /**
  * 使用 MetaMask 连接 
  * ethereum
        .request({ method: 'wallet_requestPermissions', params: [{ eth_accounts: {} }], })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });

    // 返回结果   
     [
              {
                "@context":["https://github.com/MetaMask/rpc-cap"],
                "invoker":"http://192.168.60.94:8080",
                "parentCapability":"eth_accounts",
                "id":"63749da3-6c3b-44cb-be96-c7fc9552238f",
                "date":1620438000604,
                "caveats":[
                  {
                    "type":"limitResponseLength",
                    "value":1,
                    "name":"primaryAccountOnly"
                  },
                  {
                    "type":"filterResponse",
                    "value":["0x35395900ab1335532d17d8ba362ebe45bacbc6f8"],
                    "name":"exposedAccounts"
                  }
                ]
              }
    ]
  */

  /**
   * 获取MetaMask 连接的后的结果
   * ethereum
        .request({ method: 'wallet_getPermissions' })
        .then(data => {
          console.log(data);
          console.log(JSON.stringify(data));
        })
        .catch(error => {
          if (error.code === 4001) {
            // EIP-1193 userRejectedRequest error
            console.log('Please connect to MetaMask.');
          } else {
            console.error(error);
          }
        });
   */

   /**
    * eth_call
    * {
    * "type":"web3-send-async-callback",
    * "messageId":6,
    * "payload":{
    *   "id":6,
    *   "jsonrpc":"2.0",
    *   "method":"eth_call",
    *   "params":[
    *       {
    *           "to":"0x5ba1e12693dc8f9c48aad8770482f4739beed696", 合约地址
    *           "data":"0x399542e900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000c2e074ec69a0dfb2997ba6c7d2e1e000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000240178b8bf0dfeb6719eb52da137a82d5df6aabed623dfabe5926d1dff5e994963aa6a0df0000000000000000000000000000000000000000000000000000000000000000000000000000000005ba1e12693dc8f9c48aad8770482f4739beed696000000000000000000000000000000000000000000000000000000000
    *
    * // 参数解释：http://cw.hubwiz.com/card/c/etherscan-api/1/6/11/
    * 
    */

    /**
     * BNB 智能链
     * method: wallet_addEthereumChain
     * params: [
      * {
      *  chainId: 0x38,
      *  chainName: Binance Smart Chain Mainnet,
      *  nativeCurrency: {
      *    name: BNB,
      *    symbol: bnb,
      *    decimals: 18
      * },
     *    rpcUrls: [https://bsc-dataseed1.ninicoin.io, https://bsc-dataseed1.defibit.io, https://bsc-dataseed.binance.org],
     *    blockExplorerUrls: [https://bscscan.com/]
     *  }
     * ]
     */

     /**
      * case "eth_getTransactionReceipt":
          {
            // 获取txd
            var params = payload["params"];
            var txd = params[0];
            var receipt = await ethClient.getTransactionReceipt(txd.toString());
            print('receipt---->>>$receipt'); // null
          }
          break;
        case "eth_getEncryptionPublicKey": // 申请加密公钥
          {
            _msg["result"]
                ["result"] = ["MoouigwUlqpTk/cMMTZ627d7vK77KvzTIbnFi46CFAo="];
          }
          break;
        case "eth_decrypt": // encrypt 加密处理后，解密信息
          {
            _msg["result"]["result"] = ["Message to encrypt"];
          }
          break;
      */

      /**
       * case "personal_sign": // 签名
          {
            // await ethClient.signTransaction(cred, transaction)
            _msg["result"]["result"] =
                "0xf346116c379efa562c2da6103020ffd5b831742f14d291674b7cbc55151385e625f623d1a91ca35ca130867e5f57cff7aa232463aa7b2f66e5518f42ed55e8dc1c";
          }
          break;
       */