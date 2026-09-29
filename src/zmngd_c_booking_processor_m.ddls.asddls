@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Booking Projection View'
@Metadata.ignorePropagatedAnnotations: true

@UI: {
  headerInfo: { typeName: 'Booking',
                typeNamePlural: 'Bookings',
                title: { type: #STANDARD, value: 'BookingID' } } }

@Search.searchable: true

define view entity ZMNGD_C_Booking_Processor_M
  as projection on ZMNGD_I_Booking_M
{
      @UI.facet: [ { id:            'Booking',
                       purpose:       #STANDARD,
                       type:          #IDENTIFICATION_REFERENCE,
                       label:         'Booking',
                       position:      10 },
                     { id:            'BookingSupplement',
                       purpose:       #STANDARD,
                       type:          #LINEITEM_REFERENCE,
                       label:         'Booking Supplement',
                       position:      20,
                       targetElement: '_BookSupplement'} ]

      @Search.defaultSearchElement: true
  key TravelId,

      @UI: { lineItem:       [ { position: 20, importance: #HIGH } ],
               identification: [ { position: 20 } ] }
      @Search.defaultSearchElement: true
  key BookingId,

      @UI: { lineItem:       [ { position: 30, importance: #HIGH } ],
               identification: [ { position: 30 } ] }
      BookingDate,

      @UI: { lineItem:       [ { position: 40, importance: #HIGH } ],
               identification: [ { position: 40 } ] }
      @Consumption.valueHelpDefinition: [{entity: {name: '/DMO/I_Customer_StdVH', element: 'CustomerID' }, useForValidation: true}]
      @ObjectModel.text.element: ['CustomerName']
      @Search.defaultSearchElement: true
      CustomerId,
      _Customer.LastName        as CustomerName,

      @UI: { lineItem:       [ { position: 50, importance: #HIGH } ],
               identification: [ { position: 50 } ] }
      @Consumption.valueHelpDefinition: [
          { entity: {name: '/DMO/I_Flight_StdVH', element: 'AirlineID'},
            additionalBinding: [ { localElement: 'FlightDate',   element: 'FlightDate',   usage: #RESULT},
                                 { localElement: 'ConnectionID', element: 'ConnectionID', usage: #RESULT},
                                 { localElement: 'FlightPrice',  element: 'Price',        usage: #RESULT},
                                 { localElement: 'CurrencyCode', element: 'CurrencyCode', usage: #RESULT } ],
            useForValidation: true }
        ]
      @ObjectModel.text.element: ['CarrierName']
      CarrierId,
      _Carrier.Name             as CarrierName,

      @UI: { lineItem:       [ { position: 60, importance: #HIGH } ],
               identification: [ { position: 60 } ] }
      @Consumption.valueHelpDefinition: [
          { entity: {name: '/DMO/I_Flight_StdVH', element: 'ConnectionID'},
            additionalBinding: [ { localElement: 'FlightDate',   element: 'FlightDate',   usage: #RESULT},
                                 { localElement: 'CarrierID',    element: 'AirlineID',    usage: #FILTER_AND_RESULT},
                                 { localElement: 'FlightPrice',  element: 'Price',        usage: #RESULT},
                                 { localElement: 'CurrencyCode', element: 'CurrencyCode', usage: #RESULT } ],
            useForValidation: true }
        ]
      ConnectionId,

      @UI: { lineItem:       [ { position: 70, importance: #HIGH } ],
               identification: [ { position: 70 } ] }
      @Consumption.valueHelpDefinition: [
          { entity: {name: '/DMO/I_Flight_StdVH', element: 'FlightDate'},
            additionalBinding: [ { localElement: 'CarrierID',    element: 'AirlineID',    usage: #FILTER_AND_RESULT},
                                 { localElement: 'ConnectionID', element: 'ConnectionID', usage: #FILTER_AND_RESULT},
                                 { localElement: 'FlightPrice',  element: 'Price',        usage: #RESULT},
                                 { localElement: 'CurrencyCode', element: 'CurrencyCode', usage: #RESULT } ],
            useForValidation: true }
        ]
      FlightDate,

      @UI: { lineItem:       [ { position: 80, importance: #HIGH } ],
               identification: [ { position: 80 } ] }
      @Semantics.amount.currencyCode: 'CurrencyCode'
      FlightPrice,

      @Consumption.valueHelpDefinition: [{entity: {name: 'I_CurrencyStdVH', element: 'Currency' }, useForValidation: true }]
      CurrencyCode,

      @UI: { lineItem:       [ { position: 90, importance: #HIGH, label: 'Status' } ],
               identification: [ { position: 90, label: 'Status' } ],
               textArrangement: #TEXT_ONLY }
      @Consumption.valueHelpDefinition: [{ entity: { name: '/DMO/I_Booking_Status_VH', element: 'BookingStatus' }}]
      @ObjectModel.text.element: ['BookingStatusText']
      BookingStatus,

      @UI.hidden: true
      _BookingStatus._Text.Text as BookingStatusText : localized,

      @UI.hidden: true
      LastChangedAt,

      /* Associations */
      _BookingStatus,
      _BookSupplement : redirected to composition child ZMNGD_C_BookSuppl_Processor_M,
      _Carrier,
      _Connection,
      _Customer,
      _Travel         : redirected to parent ZMNGD_C_TRAVEL_PROCESSOR_M
}
