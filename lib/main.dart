import 'dart:async';
import 'dart:io';
import 'dart:convert' as convert;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web3dart/crypto.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart';

// DAPP集合
List dappList = [
  'https://metamask.github.io/test-dapp/', // metamask test
  'https://app.uniswap.org/#/swap', // 兑换流程已实现（👌🏻）
  'https://pancakeswap.finance/', // BSC pancake
  "https://pancakebunny.finance/pool", // BSC bnb 质押已实现（👌🏻）
  "https://hfi.one/#/", // HECO 登录不了
  "https://depth.fi/?utm_source=tokenpocket", // HECO 登录不了
  "https://mdex.com/#/",
  "https://app.sushi.com/swap", // sushi 测试网可用
];
String currDapp = dappList[6];

List addressList = [
  "0xec8cb68f120018d169901998126c95327e0c9623", // 施
  "0x35395900Ab1335532D17D8BA362ebe45BAcbC6f8", // 我
];
String address = addressList[1]; // 当前钱包地址

List netWorkList = [
  "https://bsc-dataseed.binance.org/", // BNB主网节点
  "https://bsc-dataseed4.defibit.io",
  "https://bsc-dataseed1.ninicoin.io",
  "https://http-mainnet-node.huobichain.com", // HECO 主网节点
  "https://http-mainnet.hecochain.com", // HECO 主网节点
  "https://mainnet.infura.io/v3/9c719071327a427d8d8061e8a982a86e", // ETH主网节点
  "https://data-seed-prebsc-1-s1.binance.org:8545/", // BNB(BSC)测试网节点
  "https://ropsten.infura.io/v3/fe1603e5d5794fe7b1fb83f22db0ead5", // ropsten 测试网节点1(万星)
  "https://ropsten.infura.io/v3/9c719071327a427d8d8061e8a982a86e", // ropsten 测试网节点2(自己)
];
String network = netWorkList[4];

// 签名私钥(账户: "0x35395900Ab1335532D17D8BA362ebe45BAcbC6f8")
String privateKey = "b513064b6570aa1d0a9366c35ee42a5dea45d28b948111ccc78c77aa2e6b1892";

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

  void onMessageReceivedFun(_msg) async {
    var httpClient = new Client();
    var ethClient = new Web3Client(network, httpClient);

    print('_msg-->$_msg');
    String type = _msg['type'];
    String callBackData; // 回调给dapp的信息

    // 2、处理注入的js返回的监听
    if (type == "api-request") {
      _msg["isAllowed"] = true;
      _msg["type"] = "api-response";
      _msg["data"] = [address];
    } else if (_msg["type"] == "web3-send-async-read-only") {
      Map payload = _msg['payload'];
      String method = payload['method'];
      _msg["type"] = "web3-send-async-callback";
      _msg["result"] = {
        // 构建对应的result
        "jsonrpc": payload['jsonrpc'],
        "id": payload['id'],
      };

      switch (method) {
        case "eth_blockNumber":
          {
            // 获取最新块的编号 return 0x...
            int blockNumber = await ethClient.getBlockNumber();
            _msg["result"]["result"] = bytesToHex(
                intToBytes(BigInt.from(blockNumber)),
                include0x: true);
          }
          break;
        case "eth_chainId": // return 0x...
          {
            int chainId = await ethClient.getNetworkId();
            _msg["result"]["result"] =
                bytesToHex(intToBytes(BigInt.from(chainId)), include0x: true);
          }
          break;
        case "wallet_addEthereumChain":
          {
            // 如果提示wallet_addEthereumChain chainName: Binance Smart Chain Mainnet
            // 请切换钱包 并提示切换值 chainName的钱包
          }
          break;
        case "eth_accounts":
          {
            _msg["result"]["result"] = [address]; // 当前钱包地址
          }
          break;
        case "eth_getBalance":
          {
              EtherAmount balance = await ethClient.getBalance(EthereumAddress.fromHex(address));
              print('balance--$balance'); // EtherAmount: 7974645000000000 wei
              _msg["result"]["result"] = bytesToHex(intToBytes(balance.getInWei), include0x: true);
          }
          break;
        case "eth_call": // 获取token列表的余额
          {
            // 执行消息调用，eth_call方法调用合约，该调用仅在当前节点执行，不产生交易
            var params = payload["params"]; // 项目方的合约地址
            var _contract = params[0]["to"]; // 要调用的合约地址
            var _data = params[0]["data"]; // 调用封装数据
            try {
              var _result = await ethClient.callRaw(
                  contract: EthereumAddress.fromHex(_contract),
                  data: hexToBytes(_data));
              _msg["result"]["result"] = _result;
            } catch (err) {
              print('err-->$err');
            }
          }
          break;
        case "eth_estimateGas": // 预估gas费用
          {
            // 1、获取上一个区块的最新的gasPrice
            EtherAmount gasPrice = await ethClient.getGasPrice();
            // return 格式 "EtherAmount: 1200000000 wei"
            print("gasPrice--$gasPrice");
            var params = payload["params"]; // 构建交易的表单数据
            var sender = params[0]["from"];
            var to = params[0]["to"];
            var data = params[0]["data"];
            var value = params[0]["value"]; // 返回的格式：0x16345785d8a0000

            BigInt estimateGas = await ethClient.estimateGas(
              sender: EthereumAddress.fromHex(sender),
              to: EthereumAddress.fromHex(to),
              value: EtherAmount.fromUnitAndValue(EtherUnit.wei, value),
              amountOfGas: BigInt.from(500000),
              gasPrice: gasPrice,
              data: hexToBytes(data),
            );
            print("estimateGas-->$estimateGas"); // 返回格式 235015
            _msg["result"]["result"] = bytesToHex(intToBytes(estimateGas), include0x: true);
          }
          break;
        case "eth_sendTransaction": // 发送交易包含签名( 弹窗显示构建交易表单)
          {
            EtherAmount gasPrice = await ethClient.getGasPrice();
            var params = payload["params"];
            var gas = params[0]["gas"]; // 0x651a
            var value = params[0]["value"]; // 0xde0b6b3a7640000
            var to = params[0]["to"];

            print('gas--$gas');
            print('2222222---${hexToDartInt(gas)*1.5.toInt()}');

            var credentials = await ethClient.credentialsFromPrivateKey(privateKey);
            var txd = await ethClient.sendTransaction(
                credentials,
                Transaction(
                  to: EthereumAddress.fromHex(to),
                  gasPrice: gasPrice,
                  maxGas: (hexToDartInt(gas)*1.5).toInt(),
                  value: EtherAmount.fromUnitAndValue(EtherUnit.wei, hexToInt(value)),
                ),
                // chainId: 3, // 测试网必填写，主网可以忽略 默认是1，其他都必须加chainId (56 BNB 主网)
                fetchChainIdFromNetworkId: true
            );
            print("签名发送交易-->$txd");
            //bnb 0xf37bf4ee2cf7d25ea85f400004cdc9f40eadca61a4e9139f7c692647216c1aa0
            _msg["result"]["result"] = txd;
          }
          break;
      }
    }

    callBackData = convert.jsonEncode(_msg);
    print("callBackDataType:-->$callBackData");
    _webViewController.evaluateJavascript('''
          ReactNativeWebView.onMessage('$callBackData')
        ''');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('webviewd 注入js代码'),
      ),
      body: Builder(builder: (BuildContext context) {
        return WebView(
          initialUrl: currDapp,
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
        // alert("onMessage");

        if (callback) {
            if (data.type === "api-response") {
                if (data.permission == 'qr-code'){
                    qrCodeResponse(data, callback);
                } else if (data.isAllowed) {
                    if (data.permission == 'web3') {
                        // window.statusAppcurrentAccountAddress = data.data[0];
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
        // alert("getSyncResponse");
        if (payload.method == "eth_accounts" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
            return web3Response(payload, [window.statusAppcurrentAccountAddress])
        } else if (payload.method == "eth_coinbase" && (typeof window.statusAppcurrentAccountAddress !== "undefined")) {
            return web3Response(payload, window.statusAppcurrentAccountAddress)
        } else if (payload.method == "net_version" || payload.method == "eth_chainId"){
            return web3Response(payload, window.statusAppNetworkId)
        } else if (payload.method == "eth_uninstallFilter"){
            return web3Response(payload, true);
        } else {
            return null;
        }
    }

    var StatusAPI = function () {};

    StatusAPI.prototype.getContactCode = function () {
        // alert("getContactCode");
        return sendAPIrequest('contact-code');
    };

    var EthereumProvider = function () {};

    EthereumProvider.prototype.isStatus = true;
    EthereumProvider.prototype.status = new StatusAPI();
    EthereumProvider.prototype.isConnected = function () { return true; };

    EthereumProvider.prototype._events = {};

    EthereumProvider.prototype.on = function(name, listener) {
        // alert("on");
        if (!this._events[name]) {
          this._events[name] = [];
        }
        this._events[name].push(listener);
    }

    EthereumProvider.prototype.removeListener = function (name, listenerToRemove) {
        // alert("removeListener");
        if (!this._events[name]) {
          return
        }

        const filterListeners = (listener) => listener !== listenerToRemove;
        this._events[name] = this._events[name].filter(filterListeners);
    }

    EthereumProvider.prototype.emit = function (name, data) {
        // alert("emit");
        if (!this._events[name]) {
          return
        }
        this._events[name].forEach(cb => cb(data));
    }
    EthereumProvider.prototype.enable = function () {
        // alert("enable");
        if (window.statusAppDebug) { console.log("enable"); }
        return sendAPIrequest('web3');
    };

    EthereumProvider.prototype.scanQRCode = function (regex) {
        // alert("scanQRCode");
        return sendAPIrequest('qr-code', {regex: regex});
    };

    EthereumProvider.prototype.request = function (requestArguments)
    {
         if (window.statusAppDebug) { console.log("request: " + JSON.stringify(requestArguments)); }
         if (!requestArguments) {
           return new Error('Request is not valid.');
         }
         var method = requestArguments.method;
         // alert("request: " + method);

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

        //  var syncResponse = getSyncResponse({method: method});
        //  if (syncResponse){
        //      return new Promise(function (resolve, reject) {
        //                                 resolve(syncResponse.result);
        //                             });
        //  }

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

    // (DEPRECATED) Support for legacy send method （钱包登录）
    EthereumProvider.prototype.send = function (method, params = [])
    {
        alert("send1: " + method);
        if (window.statusAppDebug) { console.log("send (legacy): " + method);}
        return this.request({method: method, params: params});
    }

    // (DEPRECATED) Support for legacy sendSync method
    EthereumProvider.prototype.sendSync = function (payload)
    {
        // alert("sendSync");
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
      alert("sendAsync");
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
    );
  }
}
