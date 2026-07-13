---

title: Non-cash flow module  
language_tabs:

+ shell: Shell
+ http: HTTP
+ javascript: JavaScript
+ ruby: Ruby
+ python: Python
+ php: PHP
+ java: Java
+ go: Go  
toc_footers: []  
includes: []  
search: true  
code_clipboard: true  
highlight_theme: darkula  
headingLevel: 2  
generator: "@tarslib/widdershins v4.0.30"

---

# Non-cash flow module

[← Integration Guide](./README.md) · **Integration #1 — Open Platform REST API**

> For **Integration #2** (AFEN VMC V2.5 FunCodes 8000, 9000 Integral exchange), see  
> [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md#215-integral-exchange-funcode-8000)

Base URLs:

# Authentication
+ HTTP Authentication, scheme: bearer  
JWT Authorization header using the Bearer scheme.

# nonCashFlow
## POST Obtain the paginated list of non-cash flow records
POST /api/nonCashFlow/getNonCashFlowPage

> Body Request parameters
>

```yaml
Type: 0
DeviceId: ""
StartTime: ""
EndTime: ""
Page: 0
PageSize: 0

```

### Request parameters
| name | location | type | Required | explanation |
| --- | --- | --- | --- | --- |
| app_id | query | string | yes | application Id |
| method | query | string | yes | Specific API interface name |
| timestamp | query | string | yes | Timestamp, in the format of yyyy-MM-dd HH:mm:ss, with the time zone set to UTC standard time. |
| sign | query | array[string] | yes | API input parameter signature result |
| sign_method | query | string | yes | Signature algorithm, with available values being: md5, hmac-sha256. |
| body | body | object | no | none |
| » Type | body | integer(int32) | no | Type 1: WeChat  2: Alipay |
| » DeviceId | body | string | no | Equipment Number |
| » StartTime | body | string(date-time) | no | strat time(query) |
| » EndTime | body | string(date-time) | no | end time |
| » Page | body | integer(int32) | no | page number |
| » PageSize | body | integer(int32) | no | page size |


> return example
>

> 200 Response
>

```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "total": 0,
  "hasNextPage": true,
  "nonCashFlows": [
    {
      "deviceId": "string",
      "slotId": "string",
      "prId": "string",
      "tradeNO": "string",
      "prName": "string",
      "transactionID": "string",
      "salePrice": 0.1,
      "payfee": 0.1,
      "status": 0,
      "payTime": "2019-08-24T14:15:22Z"
    }
  ]
}
```

```plain
{"errCode":"string","errMsg":"string","isError":true,"total":0,"hasNextPage":true,"nonCashFlows":[{"deviceId":"string","slotId":"string","prId":"string","tradeNO":"string","prName":"string","transactionID":"string","salePrice":0.1,"payfee":0.1,"status":0,"payTime":"2019-08-24T14:15:22Z"}]}
```

### return result
| status code | status code meaning | explanation | data model |
| --- | --- | --- | --- |
| 200 | [OK](https://tools.ietf.org/html/rfc7231#section-6.3.1) | OK | [GetNonCashFlowResponse](#schemagetnoncashflowresponse) |


# data model
## GetNonCashFlowResponse
```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "total": 0,
  "hasNextPage": true,
  "nonCashFlows": [
    {
      "deviceId": "string",
      "slotId": "string",
      "prId": "string",
      "tradeNO": "string",
      "prName": "string",
      "transactionID": "string",
      "salePrice": 0.1,
      "payfee": 0.1,
      "status": 0,
      "payTime": "2019-08-24T14:15:22Z"
    }
  ]
}

```

Retrieve the list of shipment records (in pagination)

### attribute
| name | type | Required | Constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| errCode | string¦null | false | none |  | error code |
| errMsg | string¦null | false | none |  | error message |
| isError | boolean | false | read-only |  | Is the response result incorrect (true: the response is incorrect)? |
| total | integer(int32) | false | none |  | Total number of items |
| hasNextPage | boolean | false | none |  | Is there a next page? (Is there a next page?) |
| nonCashFlows | [[NonCashFlowDetail](#schemanoncashflowdetail)]¦null | false | none |  | List of Shipping Records |


## NonCashFlowDetail
```json
{
  "deviceId": "string",
  "slotId": "string",
  "prId": "string",
  "tradeNO": "string",
  "prName": "string",
  "transactionID": "string",
  "salePrice": 0.1,
  "payfee": 0.1,
  "status": 0,
  "payTime": "2019-08-24T14:15:22Z"
}

```

Delivery Record Details

### attribute
| name | type | Required | constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| deviceId | string¦null | false | none |  | equipment number |
| slotId | string¦null | false | none |  | Cargo Hold Number |
| prId | string¦null | false | none |  | product ID |
| tradeNO | string¦null | false | none |  | Merchant Order Number |
| prName | string¦null | false | none |  | Name of the sold product |
| transactionID | string¦null | false | none |  | order number |
| salePrice | number(double)¦null | false | none |  | The prices of the sold goods are: <br/>- On WeChat, they are in cents, with 1 yuan = 100 cents.<br/>- On Alipay, they are in yuan, with 1 yuan = 1 yuan. |
| payfee | number(double) | false | none |  | Order actual payment amount: WeChat is in units of fen, 1 yuan = 100 fen. Alipay is in units of yuan, 1 yuan = 1 yuan. |
| status | integer(int32)¦null | false | none |  | Order status: 0 - Paid; 1 - Shipped; 2 - Refunded; 4 - Refund Reviewing; 8 - Rejected. |
| payTime | string(date-time)¦null | false | none |  | Order payment time |


