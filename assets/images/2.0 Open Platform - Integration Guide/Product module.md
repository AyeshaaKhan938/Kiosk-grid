---

title: product module  
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

# product module

[← Integration Guide](./README.md) · **Integration #1 — Open Platform REST API**

> For **Integration #2** (AFEN VMC V2.5 FunCode 1000 Load/Delivery), see  
> [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md#211-loaddelivery-funcode-1000)

Base URLs:

# Authentication
+ HTTP Authentication, scheme: bearer  
JWT Authorization header using the Bearer scheme.

# product
## POST Obtain the paginated list of products
POST /api/product/getProductPage

> Body Request parameters
>

```yaml
Page: 0
PageSize: 0

```

### request parameters
| name | location | type | Required | explanation |
| --- | --- | --- | --- | --- |
| app_id | query | string | yes | application Id |
| method | query | string | yes | Specific API interface name |
| timestamp | query | string | yes | Timestamp, in the format of yyyy-MM-dd HH:mm:ss, with the time zone set to UTC standard time. |
| sign | query | array[string] | yes | API input parameter signature result |
| sign_method | query | string | yes | Signature algorithm, with available values being: md5, hmac-sha256. |
| body | body | object | no | none |
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
  "products": [
    {
      "prId": "string",
      "prCode": "string",
      "prName": "string",
      "prPrice": 0.1,
      "prImgUrl": "string"
    }
  ]
}
```

```plain
{"errCode":"string","errMsg":"string","isError":true,"total":0,"hasNextPage":true,"products":[{"prId":"string","prCode":"string","prName":"string","prPrice":0.1,"prImgUrl":"string"}]}
```

### return result
| status code | status code meaning | explanation | data model |
| --- | --- | --- | --- |
| 200 | [OK](https://tools.ietf.org/html/rfc7231#section-6.3.1) | OK | [GetProductResponse](#schemagetproductresponse) |


# Data model
## GetProductResponse
```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "total": 0,
  "hasNextPage": true,
  "products": [
    {
      "prId": "string",
      "prCode": "string",
      "prName": "string",
      "prPrice": 0.1,
      "prImgUrl": "string"
    }
  ]
}

```

Retrieve the list of products (with pagination)

### Attribute
| name | type | Required | Constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| errCode | string¦null | false | none |  | error code |
| errMsg | string¦null | false | none |  | error message |
| isError | boolean | false | read-only |  | Is the response result incorrect (true: the response is incorrect)? |
| total | integer(int32) | false | none |  | Total number of items |
| hasNextPage | boolean | false | none |  | Is there a next page? (Is there a subsequent page?) |
| products | [[ProductDetail](#schemaproductdetail)]¦null | false | none |  | product list |


## ProductDetail
```json
{
  "prId": "string",
  "prCode": "string",
  "prName": "string",
  "prPrice": 0.1,
  "prImgUrl": "string"
}

```

product detail

### attribute
| name | type | Required | Constraint | chinese name | explanation |
| --- | --- | --- | --- | --- | --- |
| prId | string¦null | false | none |  | product ID |
| prCode | string¦null | false | none |  | product code |
| prName | string¦null | false | none |  | product noun |
| prPrice | number(double)¦null | false | none |  | product price |
| prImgUrl | string¦null | false | none |  | product image |


