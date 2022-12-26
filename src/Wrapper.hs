{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE OverloadedStrings #-}
module Wrapper where

import           Text.RawString.QQ (r)
import           Data.Text (Text)


data HtmlEventHandler = HtmlEventHandler
  { eventType :: String -- eg submit or click
  , functionName :: String -- called whenever the event happens
  , handlingFunction :: String -- receives the event and sends the event over the websocket
  }

clickEventHandlingFunction :: String
clickEventHandlingFunction = [r|
  function handleClickEvents(event) {
    event.stopPropagation();

    var clickValue;
    try {
      clickLocation = JSON.parse(event.target.getAttribute("location"));
    } catch (error) {
      // if the action is just a string, parsing it as JSON would fail
      clickLocation = event.target.getAttribute("location");
    }
    var location = JSON.parse(event.currentTarget.getAttribute("handler"))

    if (clickLocation) {
      window.ws.send(JSON.stringify({ "event": "click", "message": clickLocation, "location": location }));
    }
  }
|]

clickEventHandler :: HtmlEventHandler
clickEventHandler = HtmlEventHandler "click" "handleClickEvents" clickEventHandlingFunction

submitEventHandlingFunction :: String
submitEventHandlingFunction = [r|
  function handleFormEvents(event) {
    event.preventDefault();
    event.stopPropagation();

    var form = new FormData(event.target);
    var entries = Object.fromEntries(form.entries());
    var location = JSON.parse(event.currentTarget.getAttribute("handler"))

    if (entries) {
      window.ws.send(JSON.stringify({ "event": "submit", "message": entries, "location": location }));
    }
  }
|]

submitEventHandler :: HtmlEventHandler
submitEventHandler = HtmlEventHandler "submit" "handleFormEvents" submitEventHandlingFunction

defaultHtmlEventHandlers :: [HtmlEventHandler]
defaultHtmlEventHandlers =
  [ clickEventHandler
  , submitEventHandler
  ]

mkBinding :: HtmlEventHandler -> String
mkBinding (HtmlEventHandler kind functionName _) =
  "item.removeEventListener(\"" <> kind <> "\", " <>  functionName <> ");"
  <> "item.addEventListener(\"" <> kind <> "\", " <>  functionName <> ");"

mkFunction :: HtmlEventHandler -> String
mkFunction (HtmlEventHandler _ _ function) = function

bindEvents :: [HtmlEventHandler] -> String
bindEvents htmlEventHandlers =
  let bindings = foldr (<>) "" $ fmap mkBinding htmlEventHandlers
      functions = foldr (<>) "" $ fmap mkFunction htmlEventHandlers
  in
    functions
    <> "function bindEvents() {"
    <> "document.querySelectorAll(\"[handler]\").forEach(item => {"
    <> bindings
    <> "});"
    <> "};"

websocketScript :: String
websocketScript = [r|
  var timeoutTime = -50;
  function connect() {
    timeoutTime += 50;
    var ws = new WebSocket("ws://localhost:8001");

    ws.onopen = () => {
      ws.send("initial from js");
      timeoutTime = 0;
    };

    ws.onmessage = evt => {
      var m = evt.data;
      console.log( m );
      console.log(JSON.parse( m ));
      var event = JSON.parse(evt.data);
      if (event.event === "setHtml") {
        // cool enough for now
        event.message.map(command => setHtml(command));
        bindEvents();
      }
    };

    ws.onclose = function() {
      setTimeout(function() {
        console.debug("Attempting to reconnect");
        connect();
      }, timeoutTime);
    };

    window.onbeforeunload = evt => {
      ws.close();
    };

    window.ws = ws;
  }
  connect();

  function getNode(location) {
    let currentNode = document.body;
    while (location.length > 0) {
      const index = location.pop();
      currentNode = currentNode.childNodes[index];
    }
    return currentNode;
  }

  function setHtml(message) {
    const command = message.message;
    const [location, newHtml] = message.contents;
    const targetNode = getNode(location);
    targetNode.outerHTML = newHtml;
  }
|]

wrapHtml :: String -> [HtmlEventHandler] -> String -> String
wrapHtml htmlHead htmlEventHandlers body =
  "<html>"
  <> "<head>"
  <> "<script>" <> websocketScript <> bindEvents htmlEventHandlers <> "bindEvents();" <> "</script>"
  <> htmlHead
  <> "</head>"
  <> "<body>"<> body <> "</body>"
  <> "</html>"
