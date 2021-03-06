{-
Copyright (C) 2015 Braden Walters

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Lesser General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License along
with this program. If not, see <http://www.gnu.org/licenses/>.
-}

module Data.Mesh3D.OBJ ( load ) where

import Control.Applicative
import Control.Monad
import qualified Data.ByteString.Lazy as LBS
import Data.Either
import Data.Maybe
import Data.Mesh3D
import Data.Monoid
import Data.Text.Encoding
import GHC.Float
import Text.PrettyPrint.ANSI.Leijen (Doc)
import Text.Trifecta

data LoadError = ParseFailed Doc deriving Show

load :: LBS.ByteString -> Either LoadError Mesh3D
load data_in =
  let loadLines = many (choice [comment, loadLine])
      parse = parseByteString loadLines mempty $ LBS.toStrict data_in
  in
    case parse of
      (Success result) -> Right $ linesToMesh result
      (Failure doc) -> Left $ ParseFailed doc

-- Parse the file into a similar data format to what appears in the file.

data LineResult =
  VertexLine Float Float Float Float |
  TexCoordLine Float Float Float |
  NormalLine Float Float Float |
  FaceLine [(Int, Maybe Int, Maybe Int)] |
  Comment String
  deriving (Show)

comment :: Parser LineResult
comment = Comment <$> (char '#' >> manyTill anyChar (try newline))

loadLine :: Parser LineResult
loadLine = do
  line_type <- choice [string "vt", string "vn", string "v", string "f"]
  _ <- spaces
  line_result <- case line_type of
                   "v" -> loadVertexLine
                   "vt" -> loadTexCoordLine
                   "vn" -> loadNormalLine
                   "f" -> loadFaceLine
  _ <- skipOptional newline
  return line_result

loadVertexLine :: Parser LineResult
loadVertexLine = do
  x <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  y <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  z <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- skipOptional spaces
  w <- double2Float <$> (fromMaybe 1.0) <$> optional
       ((either fromInteger id) <$> integerOrDouble)
  return $ VertexLine x y z w

loadTexCoordLine :: Parser LineResult
loadTexCoordLine = do
  u <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  v <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  w <- double2Float <$> (fromMaybe 0.0) <$> optional
       ((either fromInteger id) <$> integerOrDouble)
  return $ TexCoordLine u v w

loadNormalLine :: Parser LineResult
loadNormalLine = do
  x <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  y <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  _ <- spaces
  z <- double2Float <$> (either fromInteger id) <$> integerOrDouble
  return $ NormalLine x y z

loadFaceLine :: Parser LineResult
loadFaceLine =
  let invalidGroupMsg = "face vertices must contain between 1 and 3 indices"
      groupToTriple [] = unexpected invalidGroupMsg
      groupToTriple [x] = return (fromInteger x, Nothing, Nothing)
      groupToTriple [x, y] = return (fromInteger x, Just $ fromInteger y,
                                     Nothing)
      groupToTriple [x, y, z] = return (fromInteger x, Just $ fromInteger y,
                                        Just $ fromInteger z)
      groupToTriple _ = unexpected invalidGroupMsg
  in do
    groups <- (integer `sepBy1` char '/') `sepBy1` spaces
    FaceLine <$> (sequence $ map groupToTriple groups)

-- Convert [LineResult] into Mesh3D.

linesToMesh :: [LineResult] -> Mesh3D
linesToMesh lines =
  Mesh3D [linesToFrame lines] (linesToTexCoords lines) (linesToTriangles lines)
         []

linesToFrame :: [LineResult] -> Frame
linesToFrame lines =
  let vertices = [Vertex (x, y, z) | line@(VertexLine x y z w) <- lines]
      normals = [Normal (x, y, z) | line@(NormalLine x y z) <- lines]
  in Frame Nothing vertices normals

linesToTexCoords :: [LineResult] -> [TextureCoordinates]
linesToTexCoords lines =
  [TextureCoordinates (x, y) | line@(TexCoordLine x y z) <- lines]

linesToTriangles :: [LineResult] -> [Triangle]
linesToTriangles [] = []
linesToTriangles ((FaceLine vert_triples):rest) =
  let faceToTriangles (first:second:third:rest) =
        (first, second, third):(faceToTriangles (first:third:rest))
      faceToTriangles _ = []
      getVertex ((x, _, _), (y, _, _), (z, _, _)) = (x, y, z)
      getTexCoord ((_, may_t1, _), (_, may_t2, _), (_, may_t3, _)) =
        case (may_t1, may_t2, may_t3) of
          (Just x, Just y, Just z) -> Just (x, y, z)
          _ -> Nothing
      getNormal ((_, _, may_n1), (_, _, may_n2), (_, _, may_n3)) =
        case (may_n1, may_n2, may_n3) of
          (Just x, Just y, Just z) -> Just (x, y, z)
          _ -> Nothing
  in (map (\tri -> Triangle (getVertex tri) (getNormal tri) (getTexCoord tri)) $
          faceToTriangles vert_triples) ++ (linesToTriangles rest)
linesToTriangles (_:rest) = linesToTriangles rest
