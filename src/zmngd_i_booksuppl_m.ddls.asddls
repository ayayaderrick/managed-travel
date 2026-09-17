@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Book Supplement Interface View'
@Metadata.ignorePropagatedAnnotations: true

define view entity ZMNGD_I_BookSuppl_M
  as select from zmngd_booksupp_m as BookingSupplement

  association        to parent ZMNGD_I_Booking_M as _Booking        on  $projection.TravelId  = _Booking.TravelId
                                                                    and $projection.BookingId = _Booking.BookingId

  association [1..1] to /DMO/I_Travel_M          as _Travel         on  $projection.TravelId = _Travel.travel_id
  association [1..1] to /DMO/I_Supplement        as _Product        on  $projection.SupplementId = _Product.SupplementID
  association [1..*] to /DMO/I_SupplementText    as _SupplementText on  $projection.SupplementId = _SupplementText.SupplementID

{
  key travel_id             as TravelId,
  key booking_id            as BookingId,
  key booking_supplement_id as BookingSupplementId,

      supplement_id         as SupplementId,

      @Semantics.amount.currencyCode: 'CurrencyCode'
      price                 as Price,
      currency_code         as CurrencyCode,

      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at       as LastChangedAt,

      _Booking,
      _Travel,
      _Product,
      _SupplementText
}
