module Shahlaa where

import           Control.Monad.Trans.State
import           Coverage
import qualified Data.Map                  as Map
import qualified Data.Set                  as Set
import           ME
import           MEService
import           Text.Printf


data TestCase = TestCase
    { input    :: [Request]
    , output   :: [Response]
    , coverage :: [CoverageInfo]
    } deriving (Eq, Show)


type TestState = (MEState, [Response], [CoverageInfo])


initTestState :: TestState
initTestState = (initMEState, [], [])


handleRequest :: TestState -> Request -> TestState
handleRequest (s, rss, covs) rq =
    (s', rss ++ [rs], covs ++ [cov])
  where
    (rs, cov) = runState (requestHandler rq s) emptyCoverage
    s' = ME.state rs


addOracle :: [Request] -> TestCase
addOracle rqs =
    TestCase rqs rss covs
  where
    (s, rss, covs) = foldl handleRequest initTestState rqs


fSide :: Side -> String
fSide Sell = "SELL"
fSide Buy  = "BUY "


fFAK :: Bool -> String
fFAK b = if b then "FAK" else "---"


fOptional :: Maybe Int -> Int
fOptional Nothing  = 0
fOptional (Just n) = n


fOrder :: Order -> String
fOrder (LimitOrder i bi shi p q s mq fak) =
    printf "Limit\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%s\t0" i bi shi p q (fSide s) (fOptional mq) (fFAK fak)
fOrder (IcebergOrder i bi shi p q s mq fak dq ps) =
    printf "Iceberg\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%s\t%d" i bi shi p q (fSide s) (fOptional mq) (fFAK fak) ps


fTrade :: Trade -> String
fTrade (Trade p q bid sid _ _ _ _) =
    printf "\tTrade\t%d\t%d\t%d\t%d\n" p q bid sid


fTrades :: [Trade] -> String
fTrades ts = foldl (++) (printf "\tTrades\t%d\n" $ length ts) $ map fTrade ts

fRequest :: Request -> String
fRequest (NewOrderRq o) =
    printf "NewOrderRq\t\t%s\n" $ fOrder o
fRequest (CancelOrderRq rqid oid side) =
    printf "CancelOrderRq\t%d\t\t%d\t\t\t\t\t%s\n" oid rqid $ fSide side
fRequest (ReplaceOrderRq oldoid o) =
    printf "ReplaceOrderRq\t%d\t%s\n" oldoid $ fOrder o
fRequest (SetCreditRq b c) =
    printf "SetCreditRq\t%d\t%d\n" b c
fRequest (SetOwnershipRq sh i) =
    printf "SetOwnershipRq\t%d\t%d\n" sh i
fRequest (SetReferencePriceRq rp) =
    printf "SetReferencePriceRq\t%d\n" rp
fRequest (SetTotalSharesRq rp) =
    printf "SetTotalSharesRq\t%d\n" rp


fResponse :: Response -> String
fResponse (NewOrderRs s ts statesnapshot) =
    printf "NewOrderRs\t%s\n%s%s" (show s) (fTrades ts) (fState statesnapshot)
fResponse (CancelOrderRs s _ statesnapshot) =
    printf "CancelOrderRs\t%s\n%s" (show s) (fState statesnapshot)
fResponse (ReplaceOrderRs s _ ts statesnapshot) =
    printf "ReplaceOrderRs\t%s\n%s%s" (show s) (fTrades ts) (fState statesnapshot)
fResponse (SetCreditRs s _) =
    printf "SetCreditRs\t%s\n" (show s)
fResponse (SetOwnershipRs s _) =
    printf "SetOwnershipRs\t%s\n" (show s)
fResponse (SetReferencePriceRs s _) =
    printf "SetReferencePriceRs\t%s\n" (show s)
fResponse (SetTotalSharesRs s _) =
    printf "SetTotalSharesRs\t%s\n" (show s)


fMap :: Show a => Show b => String -> Map.Map a b -> String
fMap prefix m = concatMap (\(i, j) -> printf "\t%s\t%s\t%s\n" prefix (show i) (show j)) $ Map.toList m


fOrderBook :: OrderBook -> String
fOrderBook (OrderBook bq sq) = foldl (++) (printf "\tOrders\t%d\n" $ length bq + length sq) $ map (printf "\tOrder\t%s\n" . fOrder) $ bq ++ sq


fCreditInfo :: CreditInfo -> String
fCreditInfo cs = printf "\tCredits\t%d\n%s" (length cs) (fMap "Credit" cs)


fOwnershipInfo :: OwnershipInfo -> String
fOwnershipInfo os = printf "\tOwnerships\t%d\n%s" (length os) (fMap "Ownership" os)


fReferencePrice :: Price -> String
fReferencePrice = printf "\tReferencePrice\t%d\n"


fTotalShares :: Quantity -> String
fTotalShares = printf "\tTotalShares\t%d\n"


fState :: MEState -> String
fState (MEState orderBook creditInfo ownershipInfo referencePrice totalShares) =
    printf "%s%s%s%s%s" (fOrderBook orderBook) (fCreditInfo creditInfo) (fOwnershipInfo ownershipInfo) (fReferencePrice referencePrice) (fTotalShares totalShares)


fInput :: [Request] -> String
fInput rqs = foldl (++) (printf "%d\n" $ length rqs) $ map fRequest rqs


fOutput :: [Response] -> String
fOutput = concatMap fResponse


fTestCase :: TestCase -> String
fTestCase (TestCase inp out _) = fInput inp ++ fOutput out ++ "\n"


fTestSuite :: [TestCase] -> String
fTestSuite ts = foldl (\acc tc -> acc ++ fTestCase tc ++ "\n") (printf "%d\n" $ length ts) ts


coverageSetTC :: [CoverageInfo] -> Set.Set CoverageItem
coverageSetTC = Set.fromList . concat


fCoverage :: [CoverageInfo] -> String
fCoverage cs = unwords $ Set.elems $ coverageSetTC cs


fCoverageInOrder :: [CoverageInfo] -> String
fCoverageInOrder cs = unwords $ concat cs


coverageScoreTC :: TestCase -> Int
coverageScoreTC = coverageScore . concat . coverage


avgCoverageScoreTS :: [TestCase] -> Double
avgCoverageScoreTS ts = fromIntegral (sum $ map coverageScoreTC ts) / fromIntegral (length ts)
