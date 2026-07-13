---

title: device module**<font style="color:rgb(60, 81, 180);background-color:rgb(248, 244, 241);"></font>**  
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

# Device module

[← Integration Guide](./README.md) · **Integration #1 — Open Platform REST API**

> For **Integration #2** (AFEN VMC V2.5 FunCode 4000 Return cycle, 5002 Ad feedback), see  
> [AFEN VMC Protocol V2.5.md](./AFEN%20VMC%20Protocol%20V2.5.md#213-return-cycle-funcode-4000)

Base URLs:

# Authentication
+ HTTP Authentication, scheme: bearer  
JWT Authorization header using the Bearer scheme.

# device
## POST Get paginated device list
POST /api/device/getDevicePage

> Body Request parameters
>

```yaml
Page: 1
PageSize: 5

```

### Request parameters
| Name | Location | Type | Required | Explanation |
| --- | --- | --- | --- | --- |
| app_id | query | string | no | none |
| method | query | string | no | none |
| timestamp | query | string | no | none |
| sign | query | array[string] | no | none |
| sign_method | query | string | no | none |
| body | body | object | no | none |
| » Page | body | integer(int32) | no | Page number |
| » PageSize | body | integer(int32) | no | Page size |


> Return example
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
  "devices": [
    {
      "mid": "string",
      "deviceName": "string",
      "deviceGroupId": "string",
      "deviceGroupName": "string",
      "screenType": 0,
      "screenSize": 0
    }
  ]
}
```

### Return results
| Status code | Status Code Meaning | Explanation | Data Model |
| --- | --- | --- | --- |
| 200 | [OK](https://tools.ietf.org/html/rfc7231#section-6.3.1) | OK | [GetDeviceResponse](#schemagetdeviceresponse) |


# deviceSlot
## POST Get Device Slot List
POST /api/deviceSlot/getDeviceSlotList

> Body Request parameters
>

```yaml
DeviceId: ""

```

### Request parameters
| Name | Location | Type | Required | Explanation |
| --- | --- | --- | --- | --- |
| app_id | query | string | yes | none |
| method | query | string | yes | none |
| timestamp | query | string | yes | none |
| sign | query | array[string] | yes | none |
| sign_method | query | string | yes | none |
| body | body | object | no | none |
| » DeviceId | body | string | no | device id |


> Return example
>

> 200 Response
>

```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "deviceSlots": [
    {
      "slotId": 0,
      "slotStatus": 0,
      "extantQuantity": 0,
      "capacity": 0,
      "prId": "string",
      "mPrice": 0.1
    }
  ]
}
```

```plain
{"errCode":"string","errMsg":"string","isError":true,"deviceSlots":[{"slotId":0,"slotStatus":0,"extantQuantity":0,"capacity":0,"prId":"string","mPrice":0.1}]}
```

### Return results
| Status code | Status Code Meaning | Explanation | Data Model |
| --- | --- | --- | --- |
| 200 | [OK](https://tools.ietf.org/html/rfc7231#section-6.3.1) | OK | [GetDeviceSlotResponse](#schemagetdeviceslotresponse) |


# Data Model
## DeviceDetail
```json
{
  "mid": "string",
  "deviceName": "string",
  "deviceGroupId": "string",
  "deviceGroupName": "string",
  "screenType": 0,
  "screenSize": 0
}

```

Device Details

### Attribute
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| mid | string¦null | false | none |  | device id |
| deviceName | string¦null | false | none |  | device name |
| deviceGroupId | string¦null | false | none |  | Device Grouping Id |
| deviceGroupName | string¦null | false | none |  | Device Grouping Name |
| screenType | [DeviceScreenTypeEnum](#schemadevicescreentypeenum) | false | none |  | Device Screen Type    Screenless<br/>NotScreen = 0   Vertical screen   VerticalScreen = 1    Horizontal screen<br/>LandscapeScreen = 2   Square screen Square = 3    |
| screenSize | [DeviceScreenSizeEnum](#schemadevicescreensizeenum) | false | none |  | Device Screen  size   Screenless NotScreen = 0   7-inch screen<br/>SevenInchScreen = 1   Large screen   LargeScreen = 2   10.1-inch screen   TenPointOneInchScreen = 3    21.5-inch screen   TwentyOnePointFiveInchScreen = 4    |


## DeviceScreenSizeEnum
```json
0

```

Device screen size  
 Screenless  NotScreen = 0  
 7-inch screen SevenInchScreen = 1  
 Large screen LargeScreen = 2  
 10.1-inch screen TenPointOneInchScreen = 3  
 21.5-inch screen TwentyOnePointFiveInchScreen = 4  


### Attribute
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| _anonymous_ | integer(int32) | false | none |  | Device Screen Size   Screenless NotScreen = 0   7-inch screen   SevenInchScreen = 1   Large screen   LargeScreen = 2   10.1-inch screen   TenPointOneInchScreen = 3   21.5-inch screen   TwentyOnePointFiveInchScreen = 4    |


#### Enumeration value
| attribute | value |
| --- | --- |
| _anonymous_ | 0 |
| _anonymous_ | 1 |
| _anonymous_ | 2 |
| _anonymous_ | 3 |
| _anonymous_ | 4 |


## <font style="color:rgb(23, 26, 29);">Device screen type enumeration</font>
```json
0

```

<font style="color:rgb(23, 26, 29);">Device screen type</font>  
 NotScreen = 0  
 VerticalScreen = 1  
 LandscapeScreen = 2  
 Square = 3  


### <font style="color:rgb(23, 26, 29);">Attribute</font>
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| _anonymous_ | integer(int32) | false | none |  | Device Screen Type   Screenless   NotScreen = 0   Vertical screen<br/>VerticalScreen = 1   Horizontal screen LandscapeScreen = 2   Square screen<br/>Square = 3    |


#### <font style="color:rgb(23, 26, 29);">Enumeration values</font>
| attribute | number |
| --- | --- |
| _anonymous_ | 0 |
| _anonymous_ | 1 |
| _anonymous_ | 2 |
| _anonymous_ | 3 |


## GetDeviceResponse
```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "total": 0,
  "hasNextPage": true,
  "devices": [
    {
      "mid": "string",
      "deviceName": "string",
      "deviceGroupId": "string",
      "deviceGroupName": "string",
      "screenType": 0,
      "screenSize": 0
    }
  ]
}

```

Retrieve the list of devices (with pagination)

### Attribute
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| errCode | string¦null | false | none |  | error code |
| errMsg | string¦null | false | none |  | error message |
| isError | boolean | false | read-only |  | Is the response result incorrect (true: the response is incorrect)? |
| total | integer(int32) | false | none |  | total number of items |
| hasNextPage | boolean | false | none |  | Is there a next page? (Is there a subsequent page?) |
| devices | [[DeviceDetail](#schemadevicedetail)]¦null | false | none |  | device list |


## DeviceSlotDetail
```json
{
  "slotId": 0,
  "slotStatus": 0,
  "extantQuantity": 0,
  "capacity": 0,
  "prId": "string",
  "mPrice": 0.1
}

```

Details of equipment cargo holds

### Attribute
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| slotId | integer(int32) | false | none |  | Cargo Hold Number |
| slotStatus | integer(int32) | false | none |  | Cargo lane status: 1 - Normal; 2 - Fault; 3 - Inactive; 4 - Out of stock. |
| extantQuantity | integer(int32) | false | none |  | inventory |
| capacity | integer(int32) | false | none |  | capacity |
| prId | string¦null | false | none |  | product ID |
| mPrice | number(double)¦null | false | none |  | Cargo lane price (machine price) |


## GetDeviceSlotResponse
```json
{
  "errCode": "string",
  "errMsg": "string",
  "isError": true,
  "deviceSlots": [
    {
      "slotId": 0,
      "slotStatus": 0,
      "extantQuantity": 0,
      "capacity": 0,
      "prId": "string",
      "mPrice": 0.1
    }
  ]
}

```

Obtain the collection of equipment cargo holds

### Attribute
| Name | Type | Required | Constraint | Chinese Name | Explanation |
| --- | --- | --- | --- | --- | --- |
| errCode | string¦null | false | none |  | error code |
| errMsg | string¦null | false | none |  | error message |
| isError | boolean | false | read-only |  | Is the response result incorrect (true: the response is incorrect)? |
| deviceSlots | [[DeviceSlotDetail](#schemadeviceslotdetail)]¦null | false | none |  | Equipment cargo hold assembly |


