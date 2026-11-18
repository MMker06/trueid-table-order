"""
신분증 위변조 판별 CNN 학습 스크립트
- 모델: EfficientNet-B0 (timm)
- 클래스: 0=위조, 1=정품
- 데이터 구조:
    data/
      train/
        genuine/   ← 정품 신분증 이미지
        forged/    ← 위조 신분증 이미지
      val/
        genuine/
        forged/

사용법:
    python train_id_classifier.py --data_dir ./data --epochs 30 --output ./weights/id_classifier.pt
"""

import argparse
import os
from pathlib import Path

import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms
import timm
from sklearn.metrics import classification_report


def get_transforms(train: bool):
    if train:
        return transforms.Compose([
            transforms.Resize((256, 256)),
            transforms.RandomCrop(224),
            transforms.RandomHorizontalFlip(),
            transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2),
            transforms.RandomRotation(5),
            transforms.ToTensor(),
            transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
        ])
    return transforms.Compose([
        transforms.Resize((224, 224)),
        transforms.ToTensor(),
        transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225]),
    ])


def train(args):
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"학습 디바이스: {device}")

    train_ds = datasets.ImageFolder(os.path.join(args.data_dir, "train"), transform=get_transforms(True))
    val_ds = datasets.ImageFolder(os.path.join(args.data_dir, "val"), transform=get_transforms(False))

    train_loader = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, num_workers=4, pin_memory=True)
    val_loader = DataLoader(val_ds, batch_size=args.batch_size, shuffle=False, num_workers=4, pin_memory=True)

    print(f"학습 데이터: {len(train_ds)}장 | 검증 데이터: {len(val_ds)}장")
    print(f"클래스 매핑: {train_ds.class_to_idx}")

    model = timm.create_model("efficientnet_b0", pretrained=True, num_classes=2)
    model = model.to(device)

    # 초기 에폭은 분류 헤드만 학습 (backbone freeze)
    for name, param in model.named_parameters():
        if "classifier" not in name:
            param.requires_grad = False

    optimizer = torch.optim.AdamW(filter(lambda p: p.requires_grad, model.parameters()), lr=1e-3)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    criterion = nn.CrossEntropyLoss()

    best_acc = 0.0
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    for epoch in range(args.epochs):
        # 10 에폭 이후 전체 fine-tune
        if epoch == 10:
            for param in model.parameters():
                param.requires_grad = True
            optimizer = torch.optim.AdamW(model.parameters(), lr=1e-4, weight_decay=1e-4)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs - 10)
            print("전체 레이어 fine-tuning 시작")

        # 학습
        model.train()
        train_loss, train_correct = 0.0, 0
        for imgs, labels in train_loader:
            imgs, labels = imgs.to(device), labels.to(device)
            optimizer.zero_grad()
            loss = criterion(model(imgs), labels)
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * imgs.size(0)
            train_correct += (model(imgs).argmax(1) == labels).sum().item()

        scheduler.step()

        # 검증
        model.eval()
        val_correct, all_preds, all_labels = 0, [], []
        with torch.no_grad():
            for imgs, labels in val_loader:
                imgs, labels = imgs.to(device), labels.to(device)
                preds = model(imgs).argmax(1)
                val_correct += (preds == labels).sum().item()
                all_preds.extend(preds.cpu().tolist())
                all_labels.extend(labels.cpu().tolist())

        train_acc = train_correct / len(train_ds)
        val_acc = val_correct / len(val_ds)
        print(f"Epoch {epoch+1:>3}/{args.epochs} | 학습 손실: {train_loss/len(train_ds):.4f} | 학습 정확도: {train_acc:.4f} | 검증 정확도: {val_acc:.4f}")

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(model.state_dict(), output_path)
            print(f"  ✓ 최고 모델 저장 (검증 정확도: {best_acc:.4f})")

    print("\n=== 최종 검증 결과 ===")
    print(classification_report(all_labels, all_preds, target_names=["forged", "genuine"]))
    print(f"저장 경로: {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--data_dir", default="./data")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--output", default="./weights/id_classifier.pt")
    train(parser.parse_args())
