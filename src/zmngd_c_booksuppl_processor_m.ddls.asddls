@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Booking Supplement Projection View'
@Metadata.ignorePropagatedAnnotations: true

@UI: { headerInfo: { typeName:       'Booking Supplement',
                     typeNamePlural: 'Booking Supplements',
                     title:          { type: #STANDARD,
                                       label: 'Booking Supplement',
                                       value: 'BookingSupplementID' } } }
@Search.searchable: true

define view entity ZMNGD_C_BookSuppl_Processor_M
  as projection on ZMNGD_I_BookSuppl_M
{
      @UI.facet: [ { id:              'BookingSupplement',
                       purpose:         #STANDARD,
                       type:            #IDENTIFICATION_REFERENCE,
                       label:           'Booking Supplement',
                       position:        10 }  ]

      @Search.defaultSearchElement: true
  key TravelId,

      @Search.defaultSearchElement: true
  key BookingId,

      @UI: { lineItem:       [ { position: 10, importance: #HIGH } ],
               identification: [ { position: 10 } ] }
  key BookingSupplementId,

      @UI: { lineItem:       [ { position: 20, importance: #HIGH } ],
               identification: [ { position: 20 } ] }
      @Consumption.valueHelpDefinition: [
          {  entity: {name: '/DMO/I_Supplement_StdVH', element: 'SupplementID' },
             additionalBinding: [ { localElement: 'Price',        element: 'Price',        usage: #RESULT },
                                  { localElement: 'CurrencyCode', element: 'CurrencyCode', usage: #RESULT }],
             useForValidation: true }
        ]
      @ObjectModel.text.element: ['SupplementDescription']
      SupplementId,
      _SupplementText.Description as SupplementDescription : localized,

      @UI: { lineItem:       [ { position: 30, importance: #HIGH } ],
               identification: [ { position: 30 } ] }
      @Semantics.amount.currencyCode: 'CurrencyCode'
      Price,

      @Consumption.valueHelpDefinition: [{entity: {name: 'I_CurrencyStdVH', element: 'Currency' }, useForValidation: true }]
      CurrencyCode,

      @UI.hidden: true
      LastChangedAt,


      /* Associations */
      _Booking : redirected to parent ZMNGD_C_Booking_Processor_M,
      _Product,
      _SupplementText,
      _Travel  : redirected to ZMNGD_C_TRAVEL_PROCESSOR_M
}
