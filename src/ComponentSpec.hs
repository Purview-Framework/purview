{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
module ComponentSpec where

import Prelude hiding (div)
import Control.Concurrent.STM.TChan
import Test.Hspec
import Data.Aeson
import Data.Aeson.TH
import Data.Time

import Component

data TestAction = Up | Down

$(deriveJSON defaultOptions ''TestAction)

spec = parallel $ do

  describe "render" $ do

    it "can create a div" $ do
      let element = Html "div" [Text "hello world"]

      render [] element `shouldBe` "<div>hello world</div>"

    it "can add an onclick" $ do
      let element =
            Attribute (OnClick (1 :: Integer))
            $ Html "div" [Text "hello world"]

      render [] element `shouldBe`
        "<div bridge-click=1>hello world</div>"

    it "can render a message handler" $ do
      let
        actionHandler :: String -> Int -> Int
        actionHandler "up" state = 1

        handler =
          MessageHandler (0 :: Int)
            actionHandler
            (Text . show)

      render [] handler
        `shouldBe`
        "0"

    it "can render a typed action" $ do
      let element =
            Attribute (OnClick Up)
            $ Html "div" [Text "hello world"]

      render [] element `shouldBe`
        "<div bridge-click=\"Up\">hello world</div>"


  describe "applyEvent" $ do

    it "changes state" $ do
      let
        actionHandler :: String -> Int -> Int
        actionHandler "up" state = 1

        handler =
          MessageHandler (0 :: Int)
            actionHandler
            (Text . show)

      render [] handler
        `shouldBe`
        "0"

      chan <- newTChanIO

      appliedHandler <- applyEvent chan (String "up") handler

      render [] appliedHandler
        `shouldBe`
        "1"

    it "works with typed messages" $ do
      let
        actionHandler :: TestAction -> Int -> Int
        actionHandler Up state = 1

        handler =
          MessageHandler (0 :: Int)
            actionHandler
            (Text . show)

      render [] handler
        `shouldBe`
        "0"

      chan <- newTChanIO

      appliedHandler <- applyEvent chan (toJSON Up) handler

      render [] appliedHandler
        `shouldBe`
        "1"

  describe "runOnces" $ do

    it "sets hasRun to True" $ do
      let
        display time = div
          [ text (show time)
          , onClick ("setTime" :: String) $ div [ text "check time" ]
          ]

        startClock cont state = Once (\send -> send ("setTime" :: String)) False (cont state)

        timeHandler = EffectHandler Nothing handle
          where
            handle :: String -> Maybe UTCTime -> IO (Maybe UTCTime)
            handle "setTime" state = Just <$> getCurrentTime
            handle _ state = pure state

        component = timeHandler (startClock display)

      show (fst (runOnces component))
        `shouldBe`
        "EffectHandler Once True div [  \"Nothing\" Attr div [  \"check time\" ]  ] "

      length (snd (runOnces component))
        `shouldBe`
        1

    it "stops collecting the action if it has already run" $ do
      let
        display time = div
          [ text (show time)
          , onClick ("setTime" :: String) $ div [ text "check time" ]
          ]

        startClock cont state = Once (\send -> send ("setTime" :: String)) False (cont state)

        timeHandler = EffectHandler Nothing handle
          where
            handle :: String -> Maybe UTCTime -> IO (Maybe UTCTime)
            handle "setTime" state = Just <$> getCurrentTime
            handle _ state = pure state

        component = timeHandler (startClock display)

      let
        run1 = runOnces component
        run2 = runOnces (fst run1)
        run3 = runOnces (fst run2)

      length (snd run1) `shouldBe` 1
      length (snd run2) `shouldBe` 0
      length (snd run3) `shouldBe` 0  -- for a bug where it was resetting run

main = hspec spec
