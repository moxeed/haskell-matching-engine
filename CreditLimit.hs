module CreditLimit (creditLimitProc) where

import           Coverage
import qualified Data.Map  as Map
import           Decorator
import           ME


creditSpentByBuyer :: BrokerID -> [Trade] -> Int
creditSpentByBuyer buyerId ts =
    sum $
    map valueTraded $
    filter (\t -> sellerBrId t /= buyerId) ts


totalWorth :: Side -> ShareholderID -> OrderBook -> Int
totalWorth side shi ob =
    sum $
    map (\o -> price o * quantity o) $
    filter (\o -> shid o == shi) $
    queueBySide side ob


creditLimitCheck :: Order -> MEState -> [Trade] -> MEState -> Bool
creditLimitCheck order beforeTradeState ts afterTradeState
    | side order == Buy  = (creditInfo beforeTradeState) Map.! buyerId >= (creditSpentByBuyer buyerId ts) + (totalWorth Buy shi afterTrade)
    | side order == Sell = True
  where
    buyerId = brid order
    afterTrade = orderBook afterTradeState
    shi = shid order


updateCreditInfo :: Order -> [Trade] -> MEState -> MEState
updateCreditInfo order ts s
    | side order == Buy  = updateBuyerCredit order ts s'
    | side order == Sell = s'
  where
    s' = updateSellersCredit ts s


updateBuyerCredit :: Order -> [Trade] -> MEState -> MEState
updateBuyerCredit buyOrder ts s@(MEState ob ci si rp) =
    MEState ob (Map.insert buyerId newCredit ci) si rp
  where
    buyerId = brid buyOrder
    newCredit = ci Map.! buyerId - (creditSpentByBuyer buyerId ts)


updateSellersCredit :: [Trade] -> MEState -> MEState
updateSellersCredit ts (MEState ob ci si rp) =
    MEState ob ci' si rp
  where
    ci' = foldl (\m t -> Map.insertWith (+) (sellerBrId t) (valueTraded t) m) ci $
        filter (\t -> buyerBrId t /= sellerBrId t) ts


creditLimitProc :: Decorator
creditLimitProc =
    decorateOnAccept "CLP" creditLimitProcByType


creditLimitProcByType :: PartialDecorator
creditLimitProcByType (NewOrderRq o) s rs s' =
    if creditLimitCheck o s (trades rs) s'
        then (rs, updateCreditInfo o (trades rs) s') `covers` "CLP1"
        else (NewOrderRs Rejected [], s) `covers` "CLP2"

creditLimitProcByType (ReplaceOrderRq _ o) s rs s' =
    if creditLimitCheck o s (trades rs) s'
        then (rs, updateCreditInfo o (trades rs) s') `covers` "CLP3"
        else (ReplaceOrderRs Rejected Nothing [], s) `covers` "CLP4"

creditLimitProcByType _ _ rs s' =
    (rs, s') `covers` "CLP5"
