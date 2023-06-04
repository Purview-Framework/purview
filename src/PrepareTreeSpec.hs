{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveAnyClass #-}
module PrepareTreeSpec where

import Prelude hiding (div)
import Test.Hspec
import Test.QuickCheck

import TreeGenerator ()
import Events
import Component
import PrepareTree
import PrepareTree (prepareTree)

type UTCTime = Integer

getCurrentTime :: IO Integer
getCurrentTime = pure 10

spec :: SpecWith ()
spec = parallel $ do

  describe "prepareTree" $ do

    it "works across a variety of trees" $ do
      property $ \x -> show ((\(_, _, it) -> it ) (prepareTree (x :: Purview String IO)))
        `shouldContain` "always present"

    it "assigns an identifier to On actions" $ do
      let target = div
            [ onClick "setTime" $ div []
            , onClick "clearTime" $ div []
            ]
          (_, _, fixedTree) = prepareTree target

      fixedTree
        `shouldBe`
        Html "div"
          [ Attribute (On "click" (Just [0]) (const "setTime") ) $ Html "div" []
          , Attribute (On "click" (Just [1]) (const "clearTime") ) $ Html "div" []
          ]

    -- TODO: Nested On actions

    describe "collecting initial events" $ do

      it "works for handlers" $ do
        let
          handler' :: (String -> Purview String IO) -> Purview () IO
          handler' = handler [Self "up"] "" handle

          handle "up" state = (id, [])

          (initialActions, _, component) = prepareTree (handler' (const $ div []))

        initialActions `shouldBe` [InternalEvent "up" Nothing (Just [])]

        -- the next round there should be no initial actions
        let
          (initialActions', _, component') = prepareTree component

        initialActions' `shouldBe` []

      it "works for effectHandler" $ do
        let
          handler' = effectHandler' [Self "up"] "" handle

          handle "up" state = pure (state, []) :: IO (String, [DirectedEvent () String])

          (initialActions, _, component) = prepareTree (handler' (const $ div []))

        initialActions `shouldBe` [InternalEvent "up" Nothing (Just [])]

        -- the next round there should be no initial actions
        let
          (initialActions', _, component') = prepareTree component

        initialActions' `shouldBe` []

      it "works for nested handlers" $ do
        let
          parentHandler = handler' [] "" handle
          childHandler = handler' [Self "to child", Parent "to parent"] "" handle

          handle "" state = (state, [])

          component :: Purview () IO
          component = parentHandler $ \_ -> childHandler $ \_ -> div []

          (initialActions, _, _) = prepareTree component

        initialActions
          `shouldBe` [ InternalEvent "to child" Nothing (Just [0])
                     , InternalEvent "to parent" Nothing (Just [])
                     ]

    it "assigns a location to handlers" $ do
      let
        timeHandler = effectHandler [] Nothing handle

        handle :: String -> Maybe UTCTime -> IO (Maybe UTCTime -> Maybe UTCTime, [DirectedEvent String String])
        handle "setTime" _     = do
          time <- getCurrentTime
          pure (const $ Just time, [])
        handle _         state =
          pure (const state, [])

        component = timeHandler (const (Text ""))

      component `shouldBe` (EffectHandler Nothing Nothing [] Nothing handle (const (Text "")))

      let
        (_, _, graphWithLocation) = prepareTree component

      graphWithLocation `shouldBe` (EffectHandler (Just []) (Just []) [] Nothing handle (const (Text "")))

    it "assigns a different location to child handlers" $ do
      let
        timeHandler = effectHandler' [] Nothing handle

        handle :: String -> Maybe UTCTime -> IO (Maybe UTCTime, [DirectedEvent String String])
        handle "setTime" _     = do
          time <- getCurrentTime
          pure (Just time, [])
        handle _         state =
          pure (state, [])

        component = div
          [ timeHandler (const (Text ""))
          , timeHandler (const (Text ""))
          ]

        (_, _, graphWithLocation) = prepareTree component

      show graphWithLocation
        `shouldBe`
        "div [  EffectHandler Just [] Just [0] Nothing \"\" EffectHandler Just [] Just [1] Nothing \"\" ] "

    it "assigns a different location to nested handlers" $ do
      let
        timeHandler = effectHandler' [] Nothing handle

        handle :: String -> Maybe UTCTime -> IO (Maybe UTCTime, [DirectedEvent String String])
        handle "setTime" _     = do
          time <- getCurrentTime
          pure (Just time, [])
        handle _         state =
          pure (state, [])

        component =
          timeHandler (const (timeHandler (const (Text ""))))


        (_, _, graphWithLocation) = prepareTree component

      show graphWithLocation `shouldBe` "EffectHandler Just [] Just [] Nothing EffectHandler Just [] Just [0] Nothing \"\""

    it "picks up css" $ do
      let
        component = (Attribute $ Style ("123", "color: blue;")) $ div []
        (_, css, preparedTree) = prepareTree component :: ([Event], [(Hash, String)], Purview () m)

      css `shouldBe` [("123", "color: blue;")]
      show preparedTree `shouldBe` "Attr Style (\"123\",\"\") div [  ] "



main :: IO ()
main = hspec spec
