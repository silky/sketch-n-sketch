-- InterfaceStorage.elm
--
-- The necessary definitions for the in-browser and disk storage aspects of the
-- interface.
--

module InterfaceStorage (taskMailbox, saveStateLocally, loadLocalState,
                         getLocalSaves, checkAndSave, clearLocalSaves,
                         removeDialog, deleteLocalSave, installSaveState) where

-- Storage library, for in browser storage
import Storage exposing (getItem, setItem, removeItem, keys, clear)

-- JSON encode/decode libraries, as local storage only stores values as Strings
import Json.Encode as Encode
import Json.Decode exposing (Decoder, (:=), object5, string, int, bool, customDecoder)

-- Task Library
import Task exposing (Task, succeed, andThen)

-- String library
import String exposing (all)
-- Signalling functions
import Signal exposing (Mailbox, mailbox, send)

-- Types for our Model
import InterfaceModel exposing (Model, Orientation, Event, sampleModel, events)
import ExamplesGenerated as Examples

-- So we can clear the slate
import LangSvg exposing (emptyTree)

-- So we can crash appropriately
import Debug

-- The mailbox that recieves Tasks
taskMailbox : Mailbox (Task String ())
taskMailbox = mailbox (succeed ())

-- Type for the partial object that we store in localStorage
type alias PartialObject = 
    { code        : String
    , orient      : Orientation
    , showZones   : InterfaceModel.ShowZones -- Int
    , midOffsetX  : Int
    , midOffsetY  : Int
    }

-- JSON encoder for our Model
-- Note that this only converts the fields we care about saving:
-- * code : String
-- * orient      : Orientation (Vertical | Horizontal)
-- * showZones   : Bool
-- * midOffsetX  : Int
-- * midOffsetY  : Int
modelToValue : Model -> Encode.Value
modelToValue model =
    Encode.object <|
      [ ("code", Encode.string model.code)
      , ("orient", Encode.string 
            (case model.orient of
                InterfaceModel.Vertical -> "Vertical"
                InterfaceModel.Horizontal -> "Horizontal"
            )
        )
      , ("showZones", Encode.int model.showZones)
      , ("midOffsetX", Encode.int model.midOffsetX)
      , ("midOffsetY", Encode.int model.midOffsetY)
      ]

-- JSON decoder for our Model
strToModel : Decoder Model
strToModel =
    let partialObjectDecoder = object5 PartialObject
            ("code" := string)
            ("orient" := customDecoder string 
                (\v -> case v of
                    "Vertical" -> Ok InterfaceModel.Vertical
                    "Horizontal" -> Ok InterfaceModel.Horizontal
                    _ -> Err "Ill-formatted orientation"
                )
            )
            ("showZones"   := int)
            ("midOffsetX"  := int)
            ("midOffsetY"  := int)
    in customDecoder partialObjectDecoder
        (\partial -> 
            Ok { sampleModel | code <- partial.code
                             , orient <- partial.orient
                             , showZones <- partial.showZones
                             , midOffsetX <- partial.midOffsetX
                             , midOffsetY <- partial.midOffsetY
                             , fieldContents <- { value = ""
                                                , hint = "Input File Name" }
                             , startup <- False
            }
        )

-- Task to save state to local browser storage
-- Note that this is passed through as an Event and not an UpdateModel for the
-- purposes of appropriately triggering rerendering in CodeBox.
saveStateLocally : String -> Bool -> Model -> Task String ()
saveStateLocally saveName saveAs model = 
    if saveAs
      then send events.address InterfaceModel.InstallSaveState 
      else setItem saveName <| modelToValue model

-- Changes state to SaveDialog
installSaveState : Model -> Model
installSaveState oldModel = 
    { oldModel | mode <- InterfaceModel.SaveDialog oldModel.mode}

-- Task to validate save field input
checkAndSave : String -> Model -> Task String ()
checkAndSave saveName model = if
    | List.all ((/=) saveName << fst) Examples.list
        && saveName /= ""
        && not (all (\c -> c == ' ' || c == '\t') saveName) ->
                setItem saveName (modelToValue model)
                `andThen` \x -> send events.address <|
                    InterfaceModel.RemoveDialog True saveName
    | otherwise -> send events.address <|
                    InterfaceModel.UpdateModel invalidInput

-- Changes state back from SaveDialog and may or may not add new save
removeDialog : Bool -> String -> Model -> Model
removeDialog makeSave saveName oldModel = case oldModel.mode of
    InterfaceModel.SaveDialog oldmode -> case makeSave of
        True -> 
          if | saveName /= oldModel.exName &&
                  List.all ((/=) saveName) oldModel.localSaves ->
                    { oldModel | mode <- oldmode 
                               , exName <- saveName
                               , localSaves <- saveName :: oldModel.localSaves 
                    }
             | otherwise ->
                 { oldModel | mode <- oldmode 
                            , exName <- saveName }
        False -> { oldModel | mode <- oldmode }
    _ -> Debug.crash "Called removeDialog when not in SaveDialog state"

-- Indicates that input was invalid
invalidInput : Model -> Model
invalidInput oldmodel =
    let oldcontents = oldmodel.fieldContents
    in
        { oldmodel | fieldContents <- { value = ""
                                      , hint = "Invalid File Name" } }

-- Task to load state from local browser storage
loadLocalState : String -> Task String ()
loadLocalState saveName = 
    case List.filter ((==) saveName << fst) Examples.list of
        (name, thunk) :: rest ->
            send events.address <| InterfaceModel.SelectExample saveName thunk
        _ -> getItem saveName strToModel
                `andThen` \loadedModel ->
                    send events.address <| 
                        InterfaceModel.UpdateModel <| 
                            installLocalState saveName loadedModel

-- Function to update model upon state load
installLocalState : String -> Model -> Model -> Model
installLocalState saveName loadedModel oldModel = 
    { loadedModel | slate <- emptyTree
                  , exName <- saveName
                  , localSaves <- oldModel.localSaves
                  , editingMode <- Just ""
    }

-- Gets the names of all of the local saves, returned in a list of strings
getLocalSaves : Task String ()
getLocalSaves = keys `andThen` \saves -> send events.address <|
    InterfaceModel.UpdateModel <| installLocalSaves <| Debug.log "Loaded" saves

-- Installs the list of local saves
installLocalSaves : List String -> Model -> Model
installLocalSaves saves oldModel = { oldModel | localSaves <- saves }

-- Clears all local saves
clearLocalSaves : Task String ()
clearLocalSaves = clear `andThen` \_ -> send events.address <|
    InterfaceModel.UpdateModel <| \m -> { m | exName <- Examples.scratchName
                                            , localSaves <- [] }

-- Deletes a local save from the model
deleteLocalSave : String -> Task String ()
deleteLocalSave name = removeItem name `andThen` \_ -> send events.address <|
    InterfaceModel.UpdateModel <| removeLocalSave name

-- Removes a local save from the model
removeLocalSave : String -> Model -> Model
removeLocalSave name oldmodel =
    { oldmodel | localSaves <- List.filter ((/=) name) oldmodel.localSaves }
