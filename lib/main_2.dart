import 'dart:async';
import 'dart:io';
import 'dart:convert' as convert;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';

void main() => runApp(MaterialApp(home: WebViewExample()));

class WebViewExample extends StatefulWidget {
  @override
  _WebViewExampleState createState() => _WebViewExampleState();
}

class _WebViewExampleState extends State<WebViewExample> {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();

  WebViewController _webViewController;
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
  }

  void onMessageReceivedFun(result) async {
    print('result-111->$result');
    // 1、选取网络、钱包
    var isMain = false;
    var mainAddress = "0x8CCF4775B824ed8381a968a1BD7Fa1E99272A203";
    var testAddress = "0x35395900Ab1335532D17D8BA362ebe45BAcbC6f8";
    var mainNetWork =
        "https://mainnet.infura.io/v3/9c719071327a427d8d8061e8a982a86e";
    var testNetWork =
        "https://ropsten.infura.io/v3/9c719071327a427d8d8061e8a982a86e";
    var network = isMain ? mainNetWork : testNetWork;
    // ignore: unused_local_variable
    var address = isMain ? mainAddress : testAddress;

    var httpClient = new Client();
    // ignore: unused_local_variable
    var ethClient = new Web3Client(network, httpClient);
    
    print('result["type"]--${result["type"]}');
    // 2、处理注入的js返回的监听
    if(result["type"] == "api-request"){// 基础连接 connected
      // 1、允许登录
     _webViewController.evaluateJavascript('''
            var str = {
              type: "api-response",
              permission: "web3",
              messageId: 0,
              params: {},
              isAllowed: true, // 是否允许连接
              data: ["0x35395900Ab1335532D17D8BA362ebe45BAcbC6f8"]
            };
            ReactNativeWebView.onMessage(JSON.stringify(str));
    ''');
    } else if(result["type"] == "web3-send-async-read-only"){
      var method = result["payload"]["method"];
      if(method == "eth_accounts"){
          _webViewController.evaluateJavascript(
          '''
            var str = {
              type: web3-send-async-callback,
              messageId: 0,
              payload: {
                id: 0,
                jsonrpc: 2.0,
                method: eth_accounts,
              },
              params: ["0x35395900Ab1335532D17D8BA362ebe45BAcbC6f8"]
            };
            ReactNativeWebView.onMessage(JSON.stringify(str));
          '''
         );
      } else if(method == "wallet_requestPermissions"){
           _webViewController.evaluateJavascript(
          '''
            var str = {
              type: web3-send-async-callback,
              messageId: 1,
              payload: {
                id: 1,
                jsonrpc: 2.0,
                method: wallet_requestPermissions,
                params: [{eth_accounts: {}}]
              }
            };
            ReactNativeWebView.onMessage(JSON.stringify(str));
          '''
         );
      } else if(method == "wallet_getPermissions"){
           _webViewController.evaluateJavascript(
          '''
            var str = {
              type: web3-send-async-callback,
              messageId: 1,
              payload: {
                id: 1,
                jsonrpc: 2.0,
                method: wallet_getPermissions,
              }
            };
            ReactNativeWebView.onMessage(JSON.stringify(str));
          '''
         );
      }
    }

    print('result-222->$result');


    

    // var method = result["payload"]["method"];
    // if (method == "eth_accounts") {
    //   result["payload"]["params"] = [address];
    //   print('result-$result');

    // } else if (method == "eth_balance") {
    //   EtherAmount balance =
    //       await ethClient.getBalance(EthereumAddress.fromHex(address));
    //   print('balance--$balance');
    //   _webViewController.evaluateJavascript('''
    //       ReactNativeWebView.postMessage($balance);
    //     ''');
    //   print('balance--${balance.getValueInUnit(EtherUnit.ether)}');
    // }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('webviewd 注入js代码'),
      ),
      body: Builder(builder: (BuildContext context) {
        return WebView(
          initialUrl: 'https://metamask.github.io/test-dapp/',
          // initialUrl: 'https://tp-lab.tokenpocket.pro/uniswap/index.html?utm_source=tokenpocket#/swap',
          javascriptMode: JavascriptMode.unrestricted,
          gestureNavigationEnabled: false,
          onWebViewCreated: (WebViewController webViewController) {
            _webViewController = webViewController;
            _controller.complete(webViewController);
          },
          javascriptChannels: <JavascriptChannel>{
            // js 调用dart
            JavascriptChannel(
                name: 'ReactNativeWebView',
                onMessageReceived: (JavascriptMessage message) {
                  var result = convert.jsonDecode(message.message);
                  onMessageReceivedFun(result);
                })
          },
          onPageFinished: (String url) => {
            _webViewController.evaluateJavascript('''
(function(){
    if(typeof EthereumProvider === "undefined"){
    var callbackId = 0;
    var callbacks = {};

    var bridgeSend = function (data) {
        ReactNativeWebView.postMessage(JSON.stringify(data));
    }

    var history = window.history;
    var pushState = history.pushState;
    history.pushState = function(state) {
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

    function qrCodeResponse(data, callback){
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
    ReactNativeWebView.onMessage = function (message)
    {
        data = JSON.parse(message);
        var id = data.messageId;
        var callback = callbacks[id];

        if (callback) {
            if (data.type === "api-response") {
                if (data.permission == 'qr-code'){
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
            else if (data.type === "web3-send-async-callback")
            {
                if (callback.beta)
                {
                    if (data.error)
                    {
                        if (data.error.code == 4100)
                            callback.reject(new Unauthorized());
                        else
                            callback.reject(data.error);
                    }
                    else
                    {
                        callback.resolve(data.result.result);
                    }
                }
                else if (callback.results)
                {
                    callback.results.push(data.error || data.result);
                    if (callback.results.length == callback.num)
                        callback.callback(undefined, callback.results);
                }
                else
                {
                    callback.callback(data.error, data.result);
                }
            }
        }
    };

    function web3Response (payload, result){
        return {id: payload.id,
                jsonrpc: "2.0",
                result: result};
    }

    function getSyncResponse (payload) {
        alert("method: " + payload.method);
        if (payload.method == "eth_accounts" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
            return web3Response(payload, [window.statusAppcurrentAccountAddress])
        } else if (payload.method == "eth_coinbase" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
            return web3Response(payload, window.statusAppcurrentAccountAddress)
        } else if (payload.method == "net_version" || payload.method == "eth_chainId"){
            // return web3Response(payload, window.statusAppNetworkId)
            return web3Response(payload, "3")
        } else if (payload.method == "eth_uninstallFilter"){
            return web3Response(payload, true);
        } else if(payload.method == "wallet_requestPermissions" && (typeof window.statusAppcurrentAccountAddress !== "undefined")){
            return web3Response(payload, [
              { parentCapability: 'eth_accounts'}
            ])
        } else if(payload.method == "wallet_getPermissions" && (typeof window.statusAppcurrentAccountAddress !== "undefined")){
            return web3Response(payload, [
              { parentCapability: 'eth_accounts'}
            ])
        } else {
            return null;
        }
    }

    var StatusAPI = function () {};

    StatusAPI.prototype.getContactCode = function () {
        return sendAPIrequest('contact-code');
    };

    var EthereumProvider = function () {};

    EthereumProvider.prototype.isStatus = true;
    EthereumProvider.prototype.status = new StatusAPI();
    EthereumProvider.prototype.isConnected = function () { return true; };

    EthereumProvider.prototype._events = {};

    EthereumProvider.prototype.on = function(name, listener) {
        alert("on 监听");
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
        return sendAPIrequest('qr-code', {regex: regex});
    };

    EthereumProvider.prototype.request = function (requestArguments)
    {
         if (window.statusAppDebug) { console.log("request: " + JSON.stringify(requestArguments)); }
         if (!requestArguments) {
           return new Error('Request is not valid.');
         }
         var method = requestArguments.method;
         alert("request: " + method);

         if (!method) {
           return new Error('Request is not valid.');
         }

         //Support for legacy send method
         if (typeof method !== 'string') {
           return this.sendSync(method);
         }

         if (method == 'eth_requestAccounts'){
             return sendAPIrequest('web3');
         }

         var syncResponse = getSyncResponse({method: method});
         if (syncResponse){
             return new Promise(function (resolve, reject) {
                                        resolve(syncResponse.result);
                                    });
         }

         var messageId = callbackId++;
         var payload = {id:      messageId,
                        jsonrpc: "2.0",
                        method:  method,
                        params:  requestArguments.params};

         bridgeSend({type:      'web3-send-async-read-only',
                     messageId: messageId,
                     payload:   payload});

         return new Promise(function (resolve, reject) {
                                callbacks[messageId] = {beta:    true,
                                                        resolve: resolve,
                                                        reject:  reject};
                            });
    };

    // (DEPRECATED) Support for legacy send method
    EthereumProvider.prototype.send = function (method, params = [])
    {
        if (window.statusAppDebug) { console.log("send (legacy): " + method);}
        return this.request({method: method, params: params});
    }

    // (DEPRECATED) Support for legacy sendSync method
    EthereumProvider.prototype.sendSync = function (payload)
    {
        if (window.statusAppDebug) { console.log("sendSync (legacy)" + JSON.stringify(payload));}
        if (payload.method == "eth_uninstallFilter"){
            this.sendAsync(payload, function (res, err) {})
        }
        var syncResponse = getSyncResponse(payload);
        if (syncResponse){
            return syncResponse;
        } else {
            return web3Response(payload, null);
        }
    };

    // (DEPRECATED) Support for legacy sendAsync method
    EthereumProvider.prototype.sendAsync = function (payload, callback)
    {
      if (window.statusAppDebug) { console.log("sendAsync (legacy)" + JSON.stringify(payload));}
      if (!payload) {
          return new Error('Request is not valid.');
      }
      if (payload.method == 'eth_requestAccounts'){
          return sendAPIrequest('web3');
      }
      var syncResponse = getSyncResponse(payload);
      if (syncResponse && callback) {
          callback(null, syncResponse);
      }
      else
      {
          var messageId = callbackId++;

          if (Array.isArray(payload))
          {
              callbacks[messageId] = {num:      payload.length,
                                      results:  [],
                                      callback: callback};
              for (var i in payload) {
                  bridgeSend({type:      'web3-send-async-read-only',
                              messageId: messageId,
                              payload:   payload[i]});
              }
          }
          else
          {
              callbacks[messageId] = {callback: callback};
              bridgeSend({type:      'web3-send-async-read-only',
                          messageId: messageId,
                          payload:   payload});
          }
      }
    };
    }

    window.ethereum = new EthereumProvider();
})();
              ''')
          },
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          print('重新加载');
          _webViewController.reload();
        },
        child: Text("获取"),
      ),
    );
  }
}
