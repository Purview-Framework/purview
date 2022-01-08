{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GADTs #-}
module Component where

import           Data.ByteString.Lazy (ByteString)
import           Data.ByteString.Lazy.Char8 (unpack)
import           Data.Aeson
import           Data.String (fromString)
import           Data.Typeable
import           GHC.Generics
import           Control.Concurrent
import           Control.Monad
import Debug.Trace

-- For monad effects
import Control.Concurrent

data Attributes where
  -- OnClick :: Typeable a => (a -> IO ()) -> Attributes
  OnClick :: ToJSON a => a -> Attributes

data Purview a where
  Attribute :: Attributes -> Purview a -> Purview a
  Text :: String -> Purview a
  Html :: String -> [Purview a] -> Purview a
  Value :: a -> Purview a

  State
    :: state
    -> ((state, state -> m ()) -> Purview a)
    -> Purview a

  MessageHandler
    :: (FromJSON action)
    => state
    -> (action -> state -> state)
    -> (state -> Purview a)
    -> Purview a

  EffectHandler
    :: (FromJSON action)
    => state
    -> (action -> state -> IO state)
    -> (state -> Purview a)
    -> Purview a

  Effect
    :: (action -> m ())
    -> Purview a

--  MessageHandler
--    :: (Typeable action)
--    => (action -> IO ())
--    -> ((action -> b) -> Purview a)
--    -> Purview a
  -- Once :: (action -> ()) -> Purview a -> Purview a

-- a little bit to clean up defining these
div = Html "div"
text = Text
useState = State

onClick :: ToJSON a => a -> Purview b -> Purview b
onClick = Attribute . OnClick

renderAttributes :: [Attributes] -> String
renderAttributes = concatMap renderAttribute
  where
    renderAttribute (OnClick action) = " bridge-click=" <> unpack (encode action)

{-

Html Tag Children

-}

render :: [Attributes] -> Purview a -> String
render attrs tree = case tree of
  Html kind rest ->
    "<" <> kind <> renderAttributes attrs <> ">"
    <> concatMap (render attrs) rest <>
    "</" <> kind <> ">"

  Text val -> val

  Attribute attr rest ->
    render (attr:attrs) rest

  MessageHandler state _ cont ->
    render attrs (cont state)

-- rewrite :: Purview a -> Purview a
-- rewrite component = case component of
--   Attribute (OnClick fn) cont ->
--     MessageHandler handler (const $ rewrite cont)
--     where
--       handler "RUN" = fn
--   e -> rewrite e

apply :: Value -> Purview a -> IO (Purview a)
apply action component = case component of
  MessageHandler state handler cont -> pure $ case fromJSON action of
    Success action' ->
      MessageHandler (handler action' state) handler cont
    Error _ ->
      cont state

  EffectHandler state handler cont -> case fromJSON action of
    Success parsedAction -> do
      void . forkIO $ do
        newState <- handler parsedAction state
        pure newState
        pure ()

      pure $ EffectHandler state handler cont
  _ -> error "sup"

setState = undefined
