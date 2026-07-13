---

title: delivery record module  
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

# delivery record module

[← Integration Guide](./README.md) · **Integration #1 — Open Platform REST API**

> For **Integration #2** (AFEN VMC V2.5 FunCodes 2000, 5000, 5001, 5002), see  
> [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md)

Base URLs:

# Authentication
+ HTTP Authentication, scheme: bearer  
JWT Authorization header using the Bearer scheme.

# shippingRecord
## POST Obtain the paginated list of shipment records
POST /api/shippingRecord/getShippingRecordPage

> Body Request parameters
>

```yaml
DeviceId: ""
StartTime: ""
EndTime: ""
Page: 0
PageSize: 0

```

### Request parameters
| name | location | type | Required | Explanation |
| --- | --- | --- | --- | --- |
| app_id | query | string | yes | application Id |
| method | query | string | yes | Specific API interface name |
| timestamp | query | string | yes | Timestamp, in the format of yyyy-MM-dd HH:mm:ss, with the time zone set to UTC standard time. |
| sign | query | array[string] | yes | API input parameter signature result |
| sign_method | query | string | yes | Signature algorithm, with available values being: md5, hmac-sha256. |
| body | body | object | no | none |
| » DeviceId | body | string | no | Equipment Number |
| » StartTime | body | string(date-time) | no | start time(query) |
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
  "shippingRecords": [
    {
      "deviceId": "string",
      "slotId": "string",
      "prId": "string",
      "payType": 0,
      "cardId": "string",
      "salePrice": 0.1,
      "status": 0,
      "serialNumber": 0,
      "trTime": "2019-08-24T14:15:22Z",
      "addTime": "2019-08-24T14:15:22Z"
    }
  ]
}
```

```plain
{"errCode":"string","errMsg":"string","isError":true,"total":0,"hasNextPage":true,"shippingRecords":[{"deviceId":"string","slotId":"string","prId":"string","payType":0,"cardId":"string","salePrice":0.1,"status":0,"serialNumber":0,"trTime":"2019-08-24T14:15:22Z","addTime":"2019-08-24T14:15:22Z"}]}
```

### return result
| status code | status code meaning | explanation | data model |
| --- | --- | --- | --- |
| 200 | [OK](https://tools.ietf.org/html/rfc7231#section-6.3.1) | OK | [GetShippingRecordResponse](#schemagetshippingrecordresponse) |


# Data model
## GetShippingRecordResponse
```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "total": 0,
  "hasNextPage": true,
  "shippingRecords": [
    {
      "deviceId": "string",
      "slotId": "string",
      "prId": "string",
      "payType": 0,
      "cardId": "string",
      "salePrice": 0.1,
      "status": 0,
      "serialNumber": 0,
      "trTime": "2019-08-24T14:15:22Z",
      "addTime": "2019-08-24T14:15:22Z"
    }
  ]
}

```

Retrieve the list of shipment records (in pagination)

### Attribute
| name | type | Required | Constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| errCode | string¦null | false | none |  | error code |
| errMsg | string¦null | false | none |  | error message |
| isError | boolean | false | read-only |  | Is the response result incorrect (true: the response is incorrect)? |
| total | integer(int32) | false | none |  | total items |
| hasNextPage | boolean | false | none |  | Is there a next page? (Is there a subsequent page?) |
| shippingRecords | [[ShippingRecordDetail](#schemashippingrecorddetail)]¦null | false | none |  | List of Shipping Records |


## ShippingRecordDetail
```json
{
  "deviceId": "string",
  "slotId": "string",
  "prId": "string",
  "payType": 0,
  "cardId": "string",
  "salePrice": 0.1,
  "status": 0,
  "serialNumber": 0,
  "trTime": "2019-08-24T14:15:22Z",
  "addTime": "2019-08-24T14:15:22Z"
}

```

details of shipment records

### Attribute
| name | type | Required | Constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| deviceId | string¦null | false | none |  | Equipment Number |
| slotId | string¦null | false | none |  | Cargo Hold Number |
| prId | string¦null | false | none |  | product ID |
| payType | integer(int32) | false | none |  | Payment Type 0 - Cash Payment 1 - UnionPay Card 2 - Member Card Payment 4 - Member Card 5 - Bank Card 11 - WeChat Payment 12 - Alipay Sound Wave 13 - Alipay Scan Code 15 - Gift 16 - One-click Delivery 17 - Pickup Code 65 - WeChat Payment (H) 66 - Alipay Scan Code Payment (H) 67 - JD (H) 68 - WeChat Games 69 - Wing Payment 70 - ICBC Scan Code Payment 71 - WeChat Member Card 72 - QQ Wallet 73 - UnionPay Business 74 - Ping An E-Payment 75 - WeChat Facial Recognition Payment 76 - Alipay Facial Recognition Payment 79 - Liuchu Payment 89 - Alipay NFC 90 - Hubtel Payment 92 - Midtrans Payment 93 - Paycools Payment 94 - KHQR Payment 101 - Remote Delivery 255 - Other |
| cardId | string¦null | false | none |  | card number |
| salePrice | number(double)¦null | false | none |  | sales  price |
| status | integer(int32)¦null | false | none |  | shipping results  0 indicates success; any non-zero value indicates failure. |
| serial Number | integer(int64)¦null | false | none |  | serial number |
| trTime | string(date-time)¦null | false | none |  | machine time |
| addTime | string(date-time)¦null | false | none |  | server time |


