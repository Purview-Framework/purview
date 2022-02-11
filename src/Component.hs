{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GADTs #-}
module Component where

import           Data.ByteString.Lazy (ByteString)
import           Data.ByteString.Lazy.Char8 (unpack)
import           Data.Aeson
import           Data.String (fromString)
import           Data.Typeable
import           GHC.Generics
import           Control.Concurrent.STM.TChan
import           Control.Monad.STM
import           Control.Monad
import Debug.Trace

-- For monad effects
import Control.Concurrent

import Events

data Attributes where
  OnClick :: ToJSON a => a -> Attributes

data Purview a where
  Attribute :: Attributes -> Purview a -> Purview a
  Text :: String -> Purview a
  Html :: String -> [Purview a] -> Purview a
  Value :: Show a => a -> Purview a

  State
    :: state
    -> ((state, state -> m ()) -> Purview a)
    -> Purview a

  MessageHandler
    :: (FromJSON action, FromJSON state)
    => Maybe [Int]
    -> state
    -> (action -> state -> state)
    -> (state -> Purview a)
    -> Purview a

  EffectHandler
    :: (FromJSON action, FromJSON state, ToJSON state)
    => Maybe [Int]
    -> state
    -> (action -> state -> IO state)
    -> (state -> Purview a)
    -> Purview a

  Once
    :: (ToJSON action)
    => ((action -> FromEvent) -> FromEvent)
    -> Bool  -- has run
    -> Purview a
    -> Purview a

instance Show (Purview a) where
  show (EffectHandler location state action cont) = "EffectHandler " <> show location <> " " <> show (cont state)
  show (MessageHandler location state action cont) = "MessageHandler " <> show location <> " " <> show (cont state)
  show (Once _ hasRun cont) = "Once " <> show hasRun <> " " <> show cont
  show (Attribute attrs cont) = "Attr " <> show cont
  show (Text str) = show str
  show (Html kind children) =
    kind <> " [ " <> concatMap ((<>) " " . show) children <> " ] "
  show (Value value) = show value

instance Eq (Purview a) where
  a == b = show a == show b

-- Various helpers
div = Html "div"
text = Text
useState = State

messageHandler state handler cont = MessageHandler Nothing state handler cont
effectHandler state handler cont = EffectHandler Nothing state handler cont

onClick :: ToJSON a => a -> Purview b -> Purview b
onClick = Attribute . OnClick

renderAttributes :: [Attributes] -> String
renderAttributes = concatMap renderAttribute
  where
    renderAttribute (OnClick action) = " bridge-click=" <> unpack (encode action)

{-|

Takes the tree and turns it into HTML.  Attributes are passed down to children until
they reach a real HTML tag.

-}

render :: Purview a -> String
render = render' [0] []

render' :: [Integer] -> [Attributes] -> Purview a -> String
render' location attrs tree = case tree of
  Html kind rest ->
    "<" <> kind <> renderAttributes attrs <> ">"
    <> concatMap (\(newLocation, comp) -> render' (newLocation:location) attrs comp) (zip [0..] rest) <>
    "</" <> kind <> ">"

  Text val -> val

  Attribute attr rest ->
    render' location (attr:attrs) rest

  MessageHandler _ state _ cont ->
    "<div handler=\"" <> show location <> "\">" <>
      render' (0:location) attrs (cont state) <>
    "</div>"

  EffectHandler _ state _ cont ->
    "<div handler=\"" <> show location <> "\">" <>
      render' (0:location) attrs (cont state) <>
    "</div>"

  Once _ hasRun cont ->
    render' location attrs cont

{-|

This is a special case event to assign state to message handlers

-}

applyNewState :: TChan FromEvent -> Value -> Purview a -> IO (Purview a)
applyNewState eventBus message component = case component of
  MessageHandler loc state handler cont -> pure $ case fromJSON message of
    Success newState ->
      MessageHandler loc newState handler cont
    Error _ ->
      cont state

  EffectHandler loc state handler cont -> case fromJSON message of
    Success newState -> do
      pure $ EffectHandler loc newState handler cont
  x -> pure x

applyEvent :: TChan FromEvent -> Value -> Purview a -> IO (Purview a)
applyEvent eventBus message component = case component of
  MessageHandler loc state handler cont -> pure $ case fromJSON message of
    Success action' ->
      MessageHandler loc (handler action' state) handler cont
    Error _ ->
      MessageHandler loc state handler cont

  EffectHandler loc state handler cont -> case fromJSON message of
    Success parsedAction -> do
      void . forkIO $ do
        newState <- handler parsedAction state
        atomically $ writeTChan eventBus $ FromEvent
          { event = "newState"
          , message = toJSON newState
          , location = loc
          }
      pure $ EffectHandler loc state handler cont
    Error err ->
      pure $ EffectHandler loc state handler cont

  x -> pure x

{-|

For now the only special event kind is "newState" which replaces
the inner state of a Handler (Message or Effect)

-}

apply :: TChan FromEvent -> FromEvent -> Purview a -> IO (Purview a)
apply eventBus FromEvent {event=eventKind, message} component =
  case eventKind of
    "newState" -> applyNewState eventBus message component
    _          -> applyEvent eventBus message component

{-|

This walks through the tree and collects actions that should be run
only once, and sets their run value to True.  It's up to something
else to actually send the actions.

-}

prepareGraph :: Purview a -> (Purview a, [FromEvent])
prepareGraph = prepareGraph' []

type Location = [Int]

prepareGraph' :: Location -> Purview a -> (Purview a, [FromEvent])
prepareGraph' location component = case component of
  Attribute attrs cont ->
    let result = prepareGraph' location cont
    in (Attribute attrs (fst result), snd result)

  Html kind children ->
    let result = fmap (\(index, child) -> prepareGraph' (index:location) child) (zip [0..] children)
    in (Html kind (fmap fst result), concatMap snd result)

  MessageHandler loc state handler cont ->
    let
      rest = fmap (prepareGraph' (0:location)) cont
    in
      (MessageHandler (Just location) state handler (\state -> fst (rest state)), snd (rest state))

  EffectHandler loc state handler cont ->
    let
      rest = fmap (prepareGraph' (0:location)) cont
    in
      (EffectHandler (Just location) state handler (\state -> fst (rest state)), snd (rest state))

  Once effect hasRun cont ->
    let send message =
          FromEvent
            { event = "once"
            , message = toJSON message
            , location = Nothing
            }
    in if not hasRun then
        let
          rest = prepareGraph' location cont
        in
          (Once effect True (fst rest), [effect send] <> (snd rest))
       else
        let
          rest = prepareGraph' location cont
        in
          (Once effect True (fst rest), snd rest)

  component -> (component, [])
