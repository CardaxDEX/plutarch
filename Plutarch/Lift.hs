{-# LANGUAGE UndecidableInstances #-}

module Plutarch.Lift (
  PConstant (..),
  PLift (..),
  plift,
  LiftError (..),
  PDefaultUniType,
) where

import Data.Bifunctor (first)
import Data.Data (Proxy (Proxy))
import Data.Text
import qualified Data.Text as T
import GHC.Stack (HasCallStack)
import Plutarch
import Plutarch.Evaluate (evaluateScript)
import Plutarch.Internal (punsafeConstant)
import Plutarch.Prelude
import qualified Plutus.V1.Ledger.Scripts as Scripts
import qualified PlutusCore as PLC
import PlutusCore.Constant (readKnownSelf)
import qualified PlutusCore.Constant as PLC
import PlutusCore.Evaluation.Machine.Exception (
  EvaluationException,
  MachineError,
 )
import qualified UntypedPlutusCore as UPLC
import UntypedPlutusCore.Evaluation.Machine.Cek (CekUserError)

class PConstant p (h :: Type) where
  -- {-
  -- Create a Plutarch-level constant, from a Haskell value.
  --
  -- Example:
  -- > pconstant @PInteger 42
  -- -}
  pconstant :: h -> Term s p

data LiftError
  = LiftError_ScriptError Scripts.ScriptError
  | LiftError_EvalException T.Text -- Using Text, because there is no Eq possible with DeBruijn naming.
  deriving stock (Eq, Show)

class PLift (h :: Type) p where
  -- {-
  -- Convert a Plutarch term to the associated Haskell value. Fail otherwise.
  -- This will fully evaluate the arbitrary closed expression, and convert the
  -- resulting value.
  -- -}
  plift' :: ClosedTerm p -> Either LiftError h

plift :: (PLift h p, HasCallStack) => ClosedTerm p -> h
plift prog = either (error . show) id $ plift' prog

instance (PLC.DefaultUni `PLC.Contains` h, PDefaultUniType p ~ h) => PConstant p h where
  pconstant =
    punsafeConstant . PLC.Some . PLC.ValueOf (PLC.knownUniOf (Proxy @h))

instance PLC.KnownTypeIn PLC.DefaultUni (UPLC.Term PLC.DeBruijn PLC.DefaultUni PLC.DefaultFun ()) h => PLift h p where
  plift' prog =
    case evaluateScript (compile prog) of
      Left e -> Left $ LiftError_ScriptError e
      Right (_, _, Scripts.unScript -> UPLC.Program _ _ term) ->
        first (LiftError_EvalException . showEvalException) $
          readKnownSelf term

showEvalException :: EvaluationException CekUserError (MachineError PLC.DefaultFun) (UPLC.Term UPLC.DeBruijn PLC.DefaultUni PLC.DefaultFun ()) -> Text
showEvalException = T.pack . show

{- | Family of eDSL Types that map to Plutus builtin in its `DefaultUni`

 We use this in: PLC.knownUniOf $ Proxy @(PDefaultUniType a)

 TODO: can we obviate this by using something from Plutus?
-}
type family PDefaultUniType (a :: k -> Type) :: Type
